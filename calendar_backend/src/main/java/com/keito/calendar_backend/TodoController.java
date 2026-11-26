package com.keito.calendar_backend;

import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.*;

import java.time.*;
import java.time.format.DateTimeFormatter;
import java.util.*;

@RestController
@RequestMapping("/api/todos")
public class TodoController {

    private final TodoRepository todoRepository;
    private final EventRepository eventRepository;
    private final UserRepository userRepository;
    private final AuthService authService;

    public TodoController(
            TodoRepository todoRepository,
            EventRepository eventRepository,
            UserRepository userRepository,
            AuthService authService
    ) {
        this.todoRepository = todoRepository;
        this.eventRepository = eventRepository;
        this.userRepository = userRepository;
        this.authService = authService;
    }

    private Optional<User> getAuthenticatedUser(String authHeader) {
        if (authHeader == null || !authHeader.startsWith("Bearer ")) {
            return Optional.empty();
        }
        String token = authHeader.substring(7);
        return authService.parseUserIdFromToken(token)
                .flatMap(userRepository::findById);
    }

    private ZoneId resolveUserZone(User user) {
        String tz = user.getTimezone();
        if (tz == null || tz.isBlank()) {
            return ZoneOffset.UTC;
        }
        try {
            return ZoneId.of(tz.trim());
        } catch (Exception e) {
            return ZoneOffset.UTC;
        }
    }

    private LocalDateTime toUtc(LocalDateTime localDateTime, ZoneId sourceZone) {
        if (localDateTime == null) return null;
        return ZonedDateTime.of(localDateTime, sourceZone)
                .withZoneSameInstant(ZoneOffset.UTC)
                .toLocalDateTime();
    }

    private LocalDateTime fromUtc(LocalDateTime utcDateTime, ZoneId targetZone) {
        if (utcDateTime == null) return null;
        return ZonedDateTime.of(utcDateTime, ZoneOffset.UTC)
                .withZoneSameInstant(targetZone)
                .toLocalDateTime();
    }

    private LocalTime parseDueTime(String dueTimeStr) {
        if (dueTimeStr == null || dueTimeStr.isBlank()) {
            return LocalTime.of(23, 59, 59);
        }
        try {
            return LocalTime.parse(dueTimeStr.trim());
        } catch (Exception e) {
            return LocalTime.of(23, 59, 59);
        }
    }

    private void populateDisplayFields(TodoItem todo, ZoneId userZone) {
        todo.setTimezone(userZone.getId());
        if (todo.getDueDateTimeUtc() != null) {
            LocalDateTime localDue = fromUtc(todo.getDueDateTimeUtc(), userZone);
            todo.setDueDate(localDue.toLocalDate());
            if (todo.getDueTimeOn()) {
                todo.setDueTime(localDue.toLocalTime().format(DateTimeFormatter.ofPattern("HH:mm")));
            } else {
                todo.setDueTime(null);
            }
        }
        if (todo.getReminderUtc() != null) {
            todo.setReminder(fromUtc(todo.getReminderUtc(), userZone));
        } else {
            todo.setReminder(null);
        }
    }

    private void syncLinkedCalendarEvent(TodoItem todo, User user, ZoneId userZone) {
        DailyEvent linkedEvent = null;
        if (todo.getLinkedEventId() != null) {
            linkedEvent = eventRepository.findByIdAndUserId(todo.getLinkedEventId(), user.getId()).orElse(null);
        }
        if (linkedEvent == null) {
            linkedEvent = new DailyEvent();
            linkedEvent.setUserId(user.getId());
        }

        linkedEvent.setTitle(todo.getTitle());
        linkedEvent.setDescription(todo.getDescription());
        linkedEvent.setEventType(todo.getCategory());
        linkedEvent.setStartTime(null); // To-Do events use endTime only ("Due Time")
        linkedEvent.setEndTime(todo.getDueDateTimeUtc());
        linkedEvent.setEventTimezone(userZone.getId());
        linkedEvent.setStartTimezone(userZone.getId());
        linkedEvent.setEndTimezone(userZone.getId());
        linkedEvent.setIsAllDay(!todo.getDueTimeOn());
        linkedEvent.setIsRepeating(false);
        linkedEvent.setRepeatType("None");
        linkedEvent.setEndOn(false);
        linkedEvent.setRepeatEndOn(null);
        linkedEvent.setSeriesId(null);
        linkedEvent.setIsTodo(true);
        linkedEvent.setIsComplete(todo.getIsComplete());
        linkedEvent.setLinkedTodoId(todo.getId());

        DailyEvent savedEvent = eventRepository.save(linkedEvent);
        if (!Objects.equals(todo.getLinkedEventId(), savedEvent.getId())) {
            todo.setLinkedEventId(savedEvent.getId());
            todoRepository.save(todo);
        }
    }

    // 1. Get all todos for authenticated user
    @GetMapping
    @Transactional(readOnly = true)
    public ResponseEntity<?> getAllTodos(
            @RequestHeader(value = "Authorization", required = false) String authHeader
    ) {
        Optional<User> userOpt = getAuthenticatedUser(authHeader);
        if (userOpt.isEmpty()) {
            return ResponseEntity.status(HttpStatus.UNAUTHORIZED).body(Map.of("error", "Unauthorized"));
        }

        User user = userOpt.get();
        ZoneId userZone = resolveUserZone(user);
        List<TodoItem> todos = todoRepository.findByUserId(user.getId());

        for (TodoItem todo : todos) {
            populateDisplayFields(todo, userZone);
        }

        todos.sort(Comparator
                .comparing(TodoItem::getIsComplete)
                .thenComparing(TodoItem::getIsFavorite, Comparator.reverseOrder())
                .thenComparing(TodoItem::getDueDateTimeUtc, Comparator.nullsLast(Comparator.naturalOrder())));

        return ResponseEntity.ok(todos);
    }

    // 2. Create a new todo + auto-create linked DailyEvent
    @PostMapping({"", "/"})
    @Transactional
    public ResponseEntity<?> createTodo(
            @RequestHeader(value = "Authorization", required = false) String authHeader,
            @RequestBody TodoItem request
    ) {
        Optional<User> userOpt = getAuthenticatedUser(authHeader);
        if (userOpt.isEmpty()) {
            return ResponseEntity.status(HttpStatus.UNAUTHORIZED).body(Map.of("error", "Unauthorized"));
        }
        if (request.getTitle() == null || request.getTitle().isBlank()) {
            return ResponseEntity.badRequest().body(Map.of("error", "Title is required"));
        }

        User user = userOpt.get();
        ZoneId userZone = resolveUserZone(user);

        LocalDate targetDate = request.getDueDate() != null ? request.getDueDate() : LocalDate.now(userZone);
        boolean dueTimeOn = request.getDueTimeOn();
        LocalTime targetTime = dueTimeOn ? parseDueTime(request.getDueTime()) : LocalTime.of(23, 59, 59);
        LocalDateTime localDue = LocalDateTime.of(targetDate, targetTime);

        TodoItem todo = new TodoItem();
        todo.setUserId(user.getId());
        todo.setTitle(request.getTitle().trim());
        todo.setDescription(request.getDescription() != null ? request.getDescription() : "");
        todo.setCategory((request.getCategory() != null && !request.getCategory().isBlank()) ? request.getCategory() : "Task");
        todo.setPriority((request.getPriority() != null && !request.getPriority().isBlank()) ? request.getPriority().toUpperCase() : "MEDIUM");
        todo.setIsFavorite(request.getIsFavorite());
        todo.setIsComplete(request.getIsComplete());
        todo.setDueTimeOn(dueTimeOn);
        todo.setDueDateTimeUtc(toUtc(localDue, userZone));
        todo.setReminderUtc(toUtc(request.getReminder(), userZone));

        TodoItem savedTodo = todoRepository.save(todo);
        syncLinkedCalendarEvent(savedTodo, user, userZone);
        populateDisplayFields(savedTodo, userZone);

        return ResponseEntity.status(HttpStatus.CREATED).body(savedTodo);
    }

    // 3. Update an existing todo + sync linked DailyEvent
    @PutMapping("/{id}")
    @Transactional
    public ResponseEntity<?> updateTodo(
            @RequestHeader(value = "Authorization", required = false) String authHeader,
            @PathVariable Long id,
            @RequestBody TodoItem request
    ) {
        Optional<User> userOpt = getAuthenticatedUser(authHeader);
        if (userOpt.isEmpty()) {
            return ResponseEntity.status(HttpStatus.UNAUTHORIZED).body(Map.of("error", "Unauthorized"));
        }

        User user = userOpt.get();
        Optional<TodoItem> existingOpt = todoRepository.findByIdAndUserId(id, user.getId());
        if (existingOpt.isEmpty()) {
            return ResponseEntity.status(HttpStatus.NOT_FOUND).body(Map.of("error", "Todo not found"));
        }

        ZoneId userZone = resolveUserZone(user);
        TodoItem existing = existingOpt.get();

        LocalDate fallbackDate = existing.getDueDateTimeUtc() != null
                ? fromUtc(existing.getDueDateTimeUtc(), userZone).toLocalDate()
                : LocalDate.now(userZone);
        LocalDate targetDate = request.getDueDate() != null ? request.getDueDate() : fallbackDate;
        boolean dueTimeOn = request.getDueTimeOn();
        LocalTime targetTime = dueTimeOn ? parseDueTime(request.getDueTime()) : LocalTime.of(23, 59, 59);
        LocalDateTime localDue = LocalDateTime.of(targetDate, targetTime);

        if (request.getTitle() != null && !request.getTitle().isBlank()) {
            existing.setTitle(request.getTitle().trim());
        }
        existing.setDescription(request.getDescription() != null ? request.getDescription() : "");
        if (request.getCategory() != null && !request.getCategory().isBlank()) {
            existing.setCategory(request.getCategory());
        }
        if (request.getPriority() != null && !request.getPriority().isBlank()) {
            existing.setPriority(request.getPriority().toUpperCase());
        }
        existing.setIsFavorite(request.getIsFavorite());
        existing.setIsComplete(request.getIsComplete());
        existing.setDueTimeOn(dueTimeOn);
        existing.setDueDateTimeUtc(toUtc(localDue, userZone));
        existing.setReminderUtc(toUtc(request.getReminder(), userZone));

        TodoItem savedTodo = todoRepository.save(existing);
        syncLinkedCalendarEvent(savedTodo, user, userZone);
        populateDisplayFields(savedTodo, userZone);

        return ResponseEntity.ok(savedTodo);
    }

    // 4. Quick toggle completion status + sync linked DailyEvent
    @RequestMapping(value = "/{id}/toggle", method = {RequestMethod.PATCH, RequestMethod.PUT, RequestMethod.POST})
    @Transactional
    public ResponseEntity<?> toggleComplete(
            @RequestHeader(value = "Authorization", required = false) String authHeader,
            @PathVariable Long id
    ) {
        Optional<User> userOpt = getAuthenticatedUser(authHeader);
        if (userOpt.isEmpty()) {
            return ResponseEntity.status(HttpStatus.UNAUTHORIZED).body(Map.of("error", "Unauthorized"));
        }

        User user = userOpt.get();
        Optional<TodoItem> existingOpt = todoRepository.findByIdAndUserId(id, user.getId());
        if (existingOpt.isEmpty()) {
            return ResponseEntity.status(HttpStatus.NOT_FOUND).body(Map.of("error", "Todo not found"));
        }

        ZoneId userZone = resolveUserZone(user);
        TodoItem todo = existingOpt.get();
        todo.setIsComplete(!todo.getIsComplete());
        TodoItem saved = todoRepository.save(todo);
        syncLinkedCalendarEvent(saved, user, userZone);
        populateDisplayFields(saved, userZone);

        return ResponseEntity.ok(saved);
    }

    // 5. Quick toggle favorite status
    @RequestMapping(value = "/{id}/favorite", method = {RequestMethod.PATCH, RequestMethod.PUT, RequestMethod.POST})
    @Transactional
    public ResponseEntity<?> toggleFavorite(
            @RequestHeader(value = "Authorization", required = false) String authHeader,
            @PathVariable Long id
    ) {
        Optional<User> userOpt = getAuthenticatedUser(authHeader);
        if (userOpt.isEmpty()) {
            return ResponseEntity.status(HttpStatus.UNAUTHORIZED).body(Map.of("error", "Unauthorized"));
        }

        User user = userOpt.get();
        Optional<TodoItem> existingOpt = todoRepository.findByIdAndUserId(id, user.getId());
        if (existingOpt.isEmpty()) {
            return ResponseEntity.status(HttpStatus.NOT_FOUND).body(Map.of("error", "Todo not found"));
        }

        ZoneId userZone = resolveUserZone(user);
        TodoItem todo = existingOpt.get();
        todo.setIsFavorite(!todo.getIsFavorite());
        TodoItem saved = todoRepository.save(todo);
        populateDisplayFields(saved, userZone);

        return ResponseEntity.ok(saved);
    }

    // 6. Delete todo + delete linked DailyEvent
    @DeleteMapping("/{id}")
    @Transactional
    public ResponseEntity<?> deleteTodo(
            @RequestHeader(value = "Authorization", required = false) String authHeader,
            @PathVariable Long id
    ) {
        Optional<User> userOpt = getAuthenticatedUser(authHeader);
        if (userOpt.isEmpty()) {
            return ResponseEntity.status(HttpStatus.UNAUTHORIZED).body(Map.of("error", "Unauthorized"));
        }

        User user = userOpt.get();
        Optional<TodoItem> existingOpt = todoRepository.findByIdAndUserId(id, user.getId());
        if (existingOpt.isEmpty()) {
            return ResponseEntity.status(HttpStatus.NOT_FOUND).body(Map.of("error", "Todo not found"));
        }

        TodoItem todo = existingOpt.get();
        if (todo.getLinkedEventId() != null) {
            eventRepository.findByIdAndUserId(todo.getLinkedEventId(), user.getId())
                    .ifPresent(eventRepository::delete);
        }
        todoRepository.delete(todo);
        return ResponseEntity.noContent().build();
    }
}

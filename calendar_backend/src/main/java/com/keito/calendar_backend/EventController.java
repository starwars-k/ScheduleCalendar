package com.keito.calendar_backend;

import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.*;

import java.time.*;
import java.util.*;

@RestController
@RequestMapping("/api/events")
public class EventController {

    private final EventRepository eventRepository;
    private final UserRepository userRepository;
    private final AuthService authService;
    private final TodoRepository todoRepository;

    public EventController(
            EventRepository eventRepository,
            UserRepository userRepository,
            AuthService authService,
            TodoRepository todoRepository
    ) {
        this.eventRepository = eventRepository;
        this.userRepository = userRepository;
        this.authService = authService;
        this.todoRepository = todoRepository;
    }

    private Optional<User> getAuthenticatedUser(String authHeader) {
        if (authHeader == null || !authHeader.startsWith("Bearer ")) {
            return Optional.empty();
        }
        String token = authHeader.substring(7);
        return authService.parseUserIdFromToken(token)
                .flatMap(userRepository::findById);
    }

    private ZoneId resolveZoneId(String zoneStr, ZoneId fallback) {
        if (zoneStr == null || zoneStr.isBlank()) {
            return fallback;
        }
        try {
            return ZoneId.of(zoneStr.trim());
        } catch (Exception e) {
            return fallback;
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

    // 1. イベント一覧取得（DBのUTC時刻をユーザーのタイムゾーンに変換して返却）
    @GetMapping({"", "/"})
    @Transactional
    public ResponseEntity<?> getAllEvents(
            @RequestHeader(value = "Authorization", required = false) String authHeader,
            @RequestParam(value = "targetYear", required = false) Integer targetYear
    ) {
        Optional<User> userOpt = getAuthenticatedUser(authHeader);
        if (userOpt.isEmpty()) {
            return ResponseEntity.status(HttpStatus.UNAUTHORIZED).body(Map.of("error", "Unauthorized"));
        }

        Long userId = userOpt.get().getId();
        List<DailyEvent> events = eventRepository.findByUserId(userId);
        ensureYearlyEventsUpTo(userId, events, targetYear);
        for (DailyEvent event : events) {
            String fallbackTz = event.getEventTimezone() != null ? event.getEventTimezone() : "UTC";
            if (event.getStartTimezone() == null || event.getStartTimezone().isBlank()) {
                event.setStartTimezone(fallbackTz);
            }
            if (event.getEndTimezone() == null || event.getEndTimezone().isBlank()) {
                event.setEndTimezone(fallbackTz);
            }
        }
        return ResponseEntity.ok(events);
    }

    private void ensureYearlyEventsUpTo(Long userId, List<DailyEvent> events, Integer targetYear) {
        Map<String, List<DailyEvent>> yearlySeriesMap = new HashMap<>();
        for (DailyEvent event : events) {
            if (event.getIsRepeating()
                    && "Yearly".equals(event.getRepeatType())
                    && event.getSeriesId() != null
                    && !event.getSeriesId().isBlank()
                    && event.getStartTime() != null
                    && event.getEndTime() != null) {
                yearlySeriesMap.computeIfAbsent(event.getSeriesId(), k -> new ArrayList<>()).add(event);
            }
        }

        List<DailyEvent> newlyGenerated = new ArrayList<>();
        for (Map.Entry<String, List<DailyEvent>> entry : yearlySeriesMap.entrySet()) {
            DailyEvent latest = entry.getValue().stream()
                    .max(Comparator.comparing(DailyEvent::getStartTime))
                    .orElse(null);
            if (latest == null) continue;

            ZoneId baseZone = resolveZoneId(latest.getEventTimezone(), ZoneOffset.UTC);
            ZoneId startZone = resolveZoneId(latest.getStartTimezone(), baseZone);
            ZoneId endZone = resolveZoneId(latest.getEndTimezone(), startZone);

            ZonedDateTime latestStart = ZonedDateTime.of(fromUtc(latest.getStartTime(), startZone), startZone);
            ZonedDateTime latestEnd = ZonedDateTime.of(fromUtc(latest.getEndTime(), endZone), endZone);
            ZonedDateTime repeatEndLimit = (latest.getEndOn() && latest.getRepeatEndOn() != null)
                    ? ZonedDateTime.of(fromUtc(latest.getRepeatEndOn(), startZone), startZone)
                    : null;

            int requestedYear = (targetYear != null) ? targetYear : LocalDate.now(startZone).getYear();
            int horizonYear = requestedYear + 9;
            if (latestStart.getYear() >= horizonYear) continue;

            int step = 1;
            while (step <= 200) {
                ZonedDateTime nextStart = latestStart.plusYears(step);
                ZonedDateTime nextEnd = latestEnd.plusYears(step);
                if (nextStart.getYear() > horizonYear) break;
                if (repeatEndLimit != null && nextStart.isAfter(repeatEndLimit)) break;

                DailyEvent occurrence = new DailyEvent(
                        latest.getTitle(),
                        latest.getDescription(),
                        nextStart.withZoneSameInstant(ZoneOffset.UTC).toLocalDateTime(),
                        nextEnd.withZoneSameInstant(ZoneOffset.UTC).toLocalDateTime(),
                        latest.getEventType(),
                        latest.getIsAllDay(),
                        true
                );
                occurrence.setUserId(userId);
                occurrence.setEventTimezone(startZone.getId());
                occurrence.setStartTimezone(startZone.getId());
                occurrence.setEndTimezone(endZone.getId());
                occurrence.setRepeatType("Yearly");
                occurrence.setEndOn(latest.getEndOn());
                occurrence.setRepeatEndOn(latest.getRepeatEndOn());
                occurrence.setSeriesId(entry.getKey());
                newlyGenerated.add(occurrence);
                step++;
            }
        }

        if (!newlyGenerated.isEmpty()) {
            events.addAll(eventRepository.saveAll(newlyGenerated));
        }
    }

    private ZonedDateTime defaultRepeatLimit(ZonedDateTime baseStart, String repeatType) {
        if (repeatType == null) return baseStart.plusYears(1);
        return switch (repeatType) {
            case "Yearly" -> baseStart.plusYears(9);
            case "Monthly" -> baseStart.plusYears(2);
            default -> baseStart.plusYears(1);
        };
    }

    private ZonedDateTime advanceByRepeatType(ZonedDateTime base, String repeatType, int step) {
        if (repeatType == null) return base.plusYears(100);
        return switch (repeatType) {
            case "Daily" -> base.plusDays(step);
            case "Weekly" -> base.plusWeeks(step);
            case "Biweekly" -> base.plusWeeks(step * 2L);
            case "Monthly" -> base.plusMonths(step);
            case "Yearly" -> base.plusYears(step);
            default -> base.plusYears(100);
        };
    }

    // 2. 新規イベント作成（isAllDayも含め、timezoneを保存し時刻をUTCに統一して保存）
    @PostMapping({"", "/"})
    public ResponseEntity<?> createEvent(
            @RequestHeader(value = "Authorization", required = false) String authHeader,
            @RequestBody DailyEvent event
    ) {
        Optional<User> userOpt = getAuthenticatedUser(authHeader);
        if (userOpt.isEmpty()) {
            return ResponseEntity.status(HttpStatus.UNAUTHORIZED).body(Map.of("error", "Unauthorized"));
        }

        User user = userOpt.get();
        ZoneId userDefaultZone = resolveZoneId(user.getTimezone(), ZoneOffset.UTC);
        ZoneId baseZone = resolveZoneId(event.getEventTimezone(), userDefaultZone);
        ZoneId startZone = resolveZoneId(event.getStartTimezone(), baseZone);
        ZoneId endZone = resolveZoneId(event.getEndTimezone(), startZone);

        if (Boolean.TRUE.equals(event.getIsTodo())) {
            LocalDateTime dueLocal = event.getEndTime() != null ? event.getEndTime() : LocalDateTime.now(endZone);
            LocalDateTime dueUtc = toUtc(dueLocal, endZone);
            event.setUserId(user.getId());
            event.setStartTime(null);
            event.setEndTime(dueUtc);
            event.setEventTimezone(endZone.getId());
            event.setStartTimezone(endZone.getId());
            event.setEndTimezone(endZone.getId());
            event.setIsRepeating(false);
            event.setRepeatType("None");
            event.setEndOn(false);
            event.setRepeatEndOn(null);
            event.setSeriesId(null);
            event.setIsTodo(true);

            DailyEvent savedEvent = eventRepository.save(event);

            TodoItem todo = new TodoItem();
            todo.setUserId(user.getId());
            todo.setTitle(savedEvent.getTitle());
            todo.setDescription(savedEvent.getDescription() != null ? savedEvent.getDescription() : "");
            todo.setCategory(savedEvent.getEventType() != null ? savedEvent.getEventType() : "Task");
            todo.setPriority("MEDIUM");
            todo.setIsFavorite(false);
            todo.setIsComplete(savedEvent.getIsComplete());
            todo.setDueTimeOn(!savedEvent.getIsAllDay());
            todo.setDueDateTimeUtc(dueUtc);
            todo.setLinkedEventId(savedEvent.getId());

            TodoItem savedTodo = todoRepository.save(todo);
            savedEvent.setLinkedTodoId(savedTodo.getId());
            savedEvent = eventRepository.save(savedEvent);

            return ResponseEntity.status(HttpStatus.CREATED).body(savedEvent);
        }

        if (!Boolean.TRUE.equals(event.getIsRepeating()) || event.getRepeatType() == null || event.getRepeatType().equals("None")) {
            event.setUserId(user.getId());
            event.setEventTimezone(startZone.getId());
            event.setStartTimezone(startZone.getId());
            event.setEndTimezone(endZone.getId());
            event.setStartTime(toUtc(event.getStartTime(), startZone));
            event.setEndTime(toUtc(event.getEndTime(), endZone));
            event.setRepeatEndOn(toUtc(event.getRepeatEndOn(), startZone));

            DailyEvent saved = eventRepository.save(event);
            return ResponseEntity.status(HttpStatus.CREATED).body(saved);
        }

        // 繰り返し予定の場合：eventZone上で日付を進めてから各回をUTCに変換して保存
        String seriesId = UUID.randomUUID().toString();
        List<DailyEvent> eventsToSave = new ArrayList<>();

        ZonedDateTime baseStart = ZonedDateTime.of(event.getStartTime(), startZone);
        ZonedDateTime baseEnd = ZonedDateTime.of(event.getEndTime(), endZone);
        ZonedDateTime limitDate = (Boolean.TRUE.equals(event.getEndOn()) && event.getRepeatEndOn() != null)
                ? ZonedDateTime.of(event.getRepeatEndOn(), startZone)
                : defaultRepeatLimit(baseStart, event.getRepeatType());

        int safetyCount = 0;
        while(safetyCount < 366){
            ZonedDateTime currentStart = advanceByRepeatType(baseStart, event.getRepeatType(), safetyCount);
            ZonedDateTime currentEnd = advanceByRepeatType(baseEnd, event.getRepeatType(), safetyCount);
            if(currentStart.isAfter(limitDate)) break;

            DailyEvent occurrence = new DailyEvent(
                    event.getTitle(),
                    event.getDescription(),
                    currentStart.withZoneSameInstant(ZoneOffset.UTC).toLocalDateTime(),
                    currentEnd.withZoneSameInstant(ZoneOffset.UTC).toLocalDateTime(),
                    event.getEventType(),
                    Boolean.TRUE.equals(event.getIsAllDay()),
                    true
            );
            occurrence.setUserId(user.getId());
            occurrence.setEventTimezone(startZone.getId());
            occurrence.setStartTimezone(startZone.getId());
            occurrence.setEndTimezone(endZone.getId());
            occurrence.setRepeatType(event.getRepeatType());
            occurrence.setEndOn(Boolean.TRUE.equals(event.getEndOn()));
            occurrence.setRepeatEndOn(toUtc(event.getRepeatEndOn(), startZone));
            occurrence.setSeriesId(seriesId);

            eventsToSave.add(occurrence);
            safetyCount++;
        }

        List<DailyEvent> savedList = eventRepository.saveAll(eventsToSave);
        return ResponseEntity.status(HttpStatus.CREATED).body(savedList);
    }

    // 3. イベント更新（isAllDayも含め、timezoneを保存し時刻をUTCに統一して保存）
    @PutMapping("/{id}")
    @Transactional
    public ResponseEntity<?> updateEvent(
            @RequestHeader(value = "Authorization", required = false) String authHeader,
            @PathVariable Long id,
            @RequestBody DailyEvent updatedEvent
    ) {
        Optional<User> userOpt = getAuthenticatedUser(authHeader);
        if (userOpt.isEmpty()) {
            return ResponseEntity.status(HttpStatus.UNAUTHORIZED).body(Map.of("error", "Unauthorized"));
        }

        User user = userOpt.get();
        Optional<DailyEvent> existingOpt = eventRepository.findById(id);
        if (existingOpt.isEmpty() || !user.getId().equals(existingOpt.get().getUserId())) {
            return ResponseEntity.status(HttpStatus.NOT_FOUND).body(Map.of("error", "Event not found"));
        }

        DailyEvent existing = existingOpt.get();
        ZoneId userDefaultZone = resolveZoneId(user.getTimezone(), ZoneOffset.UTC);
        ZoneId baseZone = resolveZoneId(updatedEvent.getEventTimezone(), userDefaultZone);
        ZoneId startZone = resolveZoneId(updatedEvent.getStartTimezone(), baseZone);
        ZoneId endZone = resolveZoneId(updatedEvent.getEndTimezone(), startZone);
        boolean shouldRepeat = Boolean.TRUE.equals(updatedEvent.getIsRepeating())
            && updatedEvent.getRepeatType() != null
            && !updatedEvent.getRepeatType().equals("None");

        existing.setTitle(updatedEvent.getTitle());
        existing.setDescription(updatedEvent.getDescription());
        existing.setEventType(updatedEvent.getEventType());
        existing.setIsAllDay(Boolean.TRUE.equals(updatedEvent.getIsAllDay()));

        if (Boolean.TRUE.equals(updatedEvent.getIsTodo())) {
            LocalDateTime dueLocal = updatedEvent.getEndTime() != null ? updatedEvent.getEndTime() : LocalDateTime.now(endZone);
            LocalDateTime dueUtc = toUtc(dueLocal, endZone);
            existing.setStartTime(null);
            existing.setEndTime(dueUtc);
            existing.setEventTimezone(endZone.getId());
            existing.setStartTimezone(endZone.getId());
            existing.setEndTimezone(endZone.getId());
            existing.setIsRepeating(false);
            existing.setRepeatType("None");
            existing.setEndOn(false);
            existing.setRepeatEndOn(null);
            existing.setSeriesId(null);
            existing.setIsTodo(true);
            existing.setIsComplete(updatedEvent.getIsComplete());

            TodoItem linkedTodo = existing.getLinkedTodoId() != null
                    ? todoRepository.findByIdAndUserId(existing.getLinkedTodoId(), user.getId()).orElse(new TodoItem())
                    : todoRepository.findByLinkedEventIdAndUserId(existing.getId(), user.getId()).orElse(new TodoItem());
            linkedTodo.setUserId(user.getId());
            linkedTodo.setTitle(existing.getTitle());
            linkedTodo.setDescription(existing.getDescription() != null ? existing.getDescription() : "");
            linkedTodo.setCategory(existing.getEventType() != null ? existing.getEventType() : "Task");
            linkedTodo.setIsComplete(existing.getIsComplete());
            linkedTodo.setDueTimeOn(!existing.getIsAllDay());
            linkedTodo.setDueDateTimeUtc(dueUtc);
            linkedTodo.setLinkedEventId(existing.getId());

            TodoItem savedTodo = todoRepository.save(linkedTodo);
            existing.setLinkedTodoId(savedTodo.getId());
            DailyEvent savedEvent = eventRepository.save(existing);
            return ResponseEntity.ok(savedEvent);
        }

        if (existing.getIsTodo() || existing.getLinkedTodoId() != null) {
            if (existing.getLinkedTodoId() != null) {
                todoRepository.findByIdAndUserId(existing.getLinkedTodoId(), user.getId())
                        .ifPresent(todoRepository::delete);
            }
            existing.setIsTodo(false);
            existing.setLinkedTodoId(null);
            existing.setIsComplete(false);
        }

        existing.setEventTimezone(startZone.getId());
        existing.setStartTimezone(startZone.getId());
        existing.setEndTimezone(endZone.getId());
        existing.setStartTime(toUtc(updatedEvent.getStartTime(), startZone));
        existing.setEndTime(toUtc(updatedEvent.getEndTime(), endZone));
        existing.setIsRepeating(shouldRepeat);
        existing.setRepeatType(shouldRepeat ? updatedEvent.getRepeatType() : "None");
        existing.setEndOn(shouldRepeat && Boolean.TRUE.equals(updatedEvent.getEndOn()));
        existing.setRepeatEndOn(shouldRepeat ? toUtc(updatedEvent.getRepeatEndOn(), startZone) : null);

        if(!shouldRepeat){
            existing.setSeriesId(null);
            DailyEvent saved = eventRepository.save(existing);
            return ResponseEntity.ok(saved);
        }
        String oldSeriesId = existing.getSeriesId();
        String seriesId = (oldSeriesId == null || oldSeriesId.isBlank())
                ? UUID.randomUUID().toString()
                : oldSeriesId;
        existing.setSeriesId(seriesId);
        DailyEvent savedFirst = eventRepository.save(existing);

        if (oldSeriesId != null && !oldSeriesId.isBlank()) {
            List<DailyEvent> oldFutureOccurrences = eventRepository.findBySeriesIdAndUserId(oldSeriesId, user.getId()).stream()
                    .filter(e -> !e.getId().equals(savedFirst.getId()))
                    .filter(e -> e.getStartTime() != null && !e.getStartTime().isBefore(savedFirst.getStartTime()))
                    .toList();
            eventRepository.deleteAll(oldFutureOccurrences);
        }

        List<DailyEvent> additionalEvents = new ArrayList<>();
        ZonedDateTime baseStart = ZonedDateTime.of(updatedEvent.getStartTime(), startZone);
        ZonedDateTime baseEnd = ZonedDateTime.of(updatedEvent.getEndTime(), endZone);
        ZonedDateTime limitDate = (Boolean.TRUE.equals(updatedEvent.getEndOn()) && updatedEvent.getRepeatEndOn() != null)
                ? ZonedDateTime.of(updatedEvent.getRepeatEndOn(), startZone)
                : defaultRepeatLimit(baseStart, updatedEvent.getRepeatType());

        int safetyCount = 1;
        while (safetyCount < 366) {
            ZonedDateTime currentStart = advanceByRepeatType(baseStart, updatedEvent.getRepeatType(), safetyCount);
            ZonedDateTime currentEnd = advanceByRepeatType(baseEnd, updatedEvent.getRepeatType(), safetyCount);
            if (currentStart.isAfter(limitDate)) break;

            DailyEvent occurrence = new DailyEvent(
                    updatedEvent.getTitle(),
                    updatedEvent.getDescription(),
                    currentStart.withZoneSameInstant(ZoneOffset.UTC).toLocalDateTime(),
                    currentEnd.withZoneSameInstant(ZoneOffset.UTC).toLocalDateTime(),
                    updatedEvent.getEventType(),
                    Boolean.TRUE.equals(updatedEvent.getIsAllDay()),
                    true
            );
            occurrence.setUserId(user.getId());
            occurrence.setEventTimezone(startZone.getId());
            occurrence.setStartTimezone(startZone.getId());
            occurrence.setEndTimezone(endZone.getId());
            occurrence.setRepeatType(updatedEvent.getRepeatType());
            occurrence.setEndOn(Boolean.TRUE.equals(updatedEvent.getEndOn()));
            occurrence.setRepeatEndOn(toUtc(updatedEvent.getRepeatEndOn(), startZone));
            occurrence.setSeriesId(seriesId);

            additionalEvents.add(occurrence);
            safetyCount++;
        }

        if (!additionalEvents.isEmpty()) {
            eventRepository.saveAll(additionalEvents);
        }
        return ResponseEntity.ok(savedFirst);
    }

    // 4. 単一イベント削除
    @DeleteMapping("/{id}")
    public ResponseEntity<?> deleteEvent(
            @RequestHeader(value = "Authorization", required = false) String authHeader,
            @PathVariable Long id
    ) {
        Optional<User> userOpt = getAuthenticatedUser(authHeader);
        if (userOpt.isEmpty()) {
            return ResponseEntity.status(HttpStatus.UNAUTHORIZED).body(Map.of("error", "Unauthorized"));
        }

        Optional<DailyEvent> existingOpt = eventRepository.findById(id);
        if (existingOpt.isEmpty() || !userOpt.get().getId().equals(existingOpt.get().getUserId())) {
            return ResponseEntity.status(HttpStatus.NOT_FOUND).body(Map.of("error", "Event not found"));
        }
        
        DailyEvent toDelete = existingOpt.get();
        if (toDelete.getLinkedTodoId() != null) {
            todoRepository.findByIdAndUserId(toDelete.getLinkedTodoId(), userOpt.get().getId())
                    .ifPresent(todoRepository::delete);
        }

        eventRepository.delete(toDelete);
        return ResponseEntity.noContent().build();
    }

    // 5. 繰り返しイベントの以降一括削除
    @DeleteMapping("/future/{id}")
    @Transactional
    public ResponseEntity<?> deleteFutureEvents(
            @RequestHeader(value = "Authorization", required = false) String authHeader,
            @PathVariable Long id
    ) {
        Optional<User> userOpt = getAuthenticatedUser(authHeader);
        if (userOpt.isEmpty()) {
            return ResponseEntity.status(HttpStatus.UNAUTHORIZED).body(Map.of("error", "Unauthorized"));
        }

        Long userId = userOpt.get().getId();
        Optional<DailyEvent> targetOpt = eventRepository.findById(id);
        if (targetOpt.isEmpty() || !userId.equals(targetOpt.get().getUserId())) {
            return ResponseEntity.status(HttpStatus.NOT_FOUND).body(Map.of("error", "Event not found"));
        }

        DailyEvent target = targetOpt.get();
        if (target.getSeriesId() == null) {
            eventRepository.delete(target);
            return ResponseEntity.noContent().build();
        }

        List<DailyEvent> toDelete = eventRepository.findByUserId(userId).stream()
                .filter(e -> target.getSeriesId().equals(e.getSeriesId()))
                .filter(e -> e.getStartTime() != null && !e.getStartTime().isBefore(target.getStartTime()))
                .toList();

        eventRepository.deleteAll(toDelete);
        return ResponseEntity.noContent().build();
    }
}
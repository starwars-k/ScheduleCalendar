package com.keito.calendar_backend;

import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.*;

import java.time.LocalDateTime;
import java.time.ZoneId;
import java.time.ZoneOffset;
import java.time.ZonedDateTime;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.UUID;

@RestController
@RequestMapping("/api/events")
public class EventController {

    private final EventRepository eventRepository;
    private final UserRepository userRepository;
    private final AuthService authService;

    public EventController(
            EventRepository eventRepository,
            UserRepository userRepository,
            AuthService authService
    ) {
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
    @GetMapping
    @Transactional(readOnly = true)
    public ResponseEntity<?> getAllEvents(
            @RequestHeader(value = "Authorization", required = false) String authHeader
    ) {
        Optional<User> userOpt = getAuthenticatedUser(authHeader);
        if (userOpt.isEmpty()) {
            return ResponseEntity.status(HttpStatus.UNAUTHORIZED).body(Map.of("error", "Unauthorized"));
        }

        User user = userOpt.get();
        ZoneId userZone = resolveZoneId(user.getTimezone(), ZoneOffset.UTC);

        List<DailyEvent> events = eventRepository.findByUserId(user.getId());
        for (DailyEvent event : events) {
            event.setStartTime(fromUtc(event.getStartTime(), userZone));
            event.setEndTime(fromUtc(event.getEndTime(), userZone));
            event.setRepeatEndOn(fromUtc(event.getRepeatEndOn(), userZone));
        }
        return ResponseEntity.ok(events);
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
        // リクエストにtimezoneが含まれていればそれを使用、なければユーザーのデフォルトを使用
        ZoneId eventZone = resolveZoneId(event.getTimezone(), userDefaultZone);

        if (!event.isRepeating() || event.getRepeatType() == null || event.getRepeatType().equals("None")) {
            event.setUserId(user.getId());
            event.setTimezone(eventZone.getId());
            event.setStartTime(toUtc(event.getStartTime(), eventZone));
            event.setEndTime(toUtc(event.getEndTime(), eventZone));
            event.setRepeatEndOn(toUtc(event.getRepeatEndOn(), eventZone));

            DailyEvent saved = eventRepository.save(event);
            return ResponseEntity.status(HttpStatus.CREATED).body(saved);
        }

        // 繰り返し予定の場合：eventZone上で日付を進めてから各回をUTCに変換して保存
        String seriesId = UUID.randomUUID().toString();
        List<DailyEvent> eventsToSave = new ArrayList<>();

        ZonedDateTime currentStart = ZonedDateTime.of(event.getStartTime(), eventZone);
        ZonedDateTime currentEnd = ZonedDateTime.of(event.getEndTime(), eventZone);
        ZonedDateTime limitDate = (event.isEndOn() && event.getRepeatEndOn() != null)
                ? ZonedDateTime.of(event.getRepeatEndOn(), eventZone)
                : currentStart.plusYears(1);

        int safetyCount = 0;
        while (!currentStart.isAfter(limitDate) && safetyCount < 366) {
            DailyEvent occurrence = new DailyEvent(
                    event.getTitle(),
                    event.getDescription(),
                    currentStart.withZoneSameInstant(ZoneOffset.UTC).toLocalDateTime(),
                    currentEnd.withZoneSameInstant(ZoneOffset.UTC).toLocalDateTime(),
                    event.getEventType(),
                    event.isAllDay(),
                    true
            );
            occurrence.setUserId(user.getId());
            occurrence.setTimezone(eventZone.getId());
            occurrence.setRepeatType(event.getRepeatType());
            occurrence.setEndOn(event.isEndOn());
            occurrence.setRepeatEndOn(toUtc(event.getRepeatEndOn(), eventZone));
            occurrence.setSeriesId(seriesId);

            eventsToSave.add(occurrence);

            switch (event.getRepeatType()) {
                case "Daily" -> {
                    currentStart = currentStart.plusDays(1);
                    currentEnd = currentEnd.plusDays(1);
                }
                case "Weekly" -> {
                    currentStart = currentStart.plusWeeks(1);
                    currentEnd = currentEnd.plusWeeks(1);
                }
                case "Biweekly" -> {
                    currentStart = currentStart.plusWeeks(2);
                    currentEnd = currentEnd.plusWeeks(2);
                }
                case "Monthly" -> {
                    currentStart = currentStart.plusMonths(1);
                    currentEnd = currentEnd.plusMonths(1);
                }
                case "Yearly" -> {
                    currentStart = currentStart.plusYears(1);
                    currentEnd = currentEnd.plusYears(1);
                }
                default -> {
                    currentStart = limitDate.plusDays(1);
                }
            }
            safetyCount++;
        }

        List<DailyEvent> savedList = eventRepository.saveAll(eventsToSave);
        return ResponseEntity.status(HttpStatus.CREATED).body(savedList);
    }

    // 3. イベント更新（isAllDayも含め、timezoneを保存し時刻をUTCに統一して保存）
    @PutMapping("/{id}")
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
        ZoneId eventZone = resolveZoneId(updatedEvent.getTimezone(), userDefaultZone);

        existing.setTitle(updatedEvent.getTitle());
        existing.setDescription(updatedEvent.getDescription());
        existing.setEventType(updatedEvent.getEventType());
        existing.setAllDay(updatedEvent.isAllDay());
        existing.setTimezone(eventZone.getId());
        existing.setStartTime(toUtc(updatedEvent.getStartTime(), eventZone));
        existing.setEndTime(toUtc(updatedEvent.getEndTime(), eventZone));
        existing.setRepeating(updatedEvent.isRepeating());
        existing.setRepeatType(updatedEvent.getRepeatType());
        existing.setEndOn(updatedEvent.isEndOn());
        existing.setRepeatEndOn(toUtc(updatedEvent.getRepeatEndOn(), eventZone));

        DailyEvent saved = eventRepository.save(existing);
        return ResponseEntity.ok(saved);
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

        eventRepository.delete(existingOpt.get());
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
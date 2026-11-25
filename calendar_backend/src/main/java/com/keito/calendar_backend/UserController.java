package com.keito.calendar_backend;

import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.time.ZoneId;
import java.time.ZonedDateTime;
import java.util.List;
import java.util.Map;
import java.util.Optional;

@RestController
@RequestMapping("/api/user")
public class UserController {

    private final UserRepository userRepository;
    private final EventRepository eventRepository;
    private final AuthService authService;

    public UserController(
            UserRepository userRepository,
            EventRepository eventRepository,
            AuthService authService
    ) {
        this.userRepository = userRepository;
        this.eventRepository = eventRepository;
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

    private Map<String, Object> buildSettingsResponse(User user) {
        return Map.of(
                "username", user.getUsername(),
                "timezone", user.getTimezone(),
                "language", user.getLanguage(),
                "enableTodoList", user.isEnableTodoList(),
                "enablePayroll", user.isEnablePayroll(),
                "setupCompleted", user.isSetupCompleted()
        );
    }

    @GetMapping("/settings")
    public ResponseEntity<?> getSettings(
            @RequestHeader(value = "Authorization", required = false) String authHeader
    ) {
        Optional<User> userOpt = getAuthenticatedUser(authHeader);
        if (userOpt.isEmpty()) {
            return ResponseEntity.status(HttpStatus.UNAUTHORIZED).body(Map.of("error", "Unauthorized"));
        }
        return ResponseEntity.ok(buildSettingsResponse(userOpt.get()));
    }

    @PutMapping("/settings")
    public ResponseEntity<?> updateSettings(
            @RequestHeader(value = "Authorization", required = false) String authHeader,
            @RequestBody Map<String, Object> request
    ) {
        Optional<User> userOpt = getAuthenticatedUser(authHeader);
        if (userOpt.isEmpty()) {
            return ResponseEntity.status(HttpStatus.UNAUTHORIZED).body(Map.of("error", "Unauthorized"));
        }

        User user = userOpt.get();

        // 1. タイムゾーン更新 & 既存イベントの時刻変換
        if (request.get("timezone") != null) {
            String newTimezoneStr = request.get("timezone").toString().trim();
            boolean convertExistingEvents = Boolean.TRUE.equals(request.get("convertExistingEvents"));

            ZoneId newZone;
            try {
                newZone = ZoneId.of(newTimezoneStr);
            } catch (Exception e) {
                return ResponseEntity.badRequest().body(Map.of("error", "Invalid timezone: " + newTimezoneStr));
            }

            ZoneId oldZone;
            try {
                oldZone = ZoneId.of(user.getTimezone());
            } catch (Exception e) {
                oldZone = ZoneId.of("UTC");
            }

            if (convertExistingEvents && !oldZone.equals(newZone)) {
                List<DailyEvent> events = eventRepository.findByUserId(user.getId());
                for (DailyEvent event : events) {
                    if (event.getStartTime() != null) {
                        event.setStartTime(
                                ZonedDateTime.of(event.getStartTime(), oldZone)
                                        .withZoneSameInstant(newZone)
                                        .toLocalDateTime()
                        );
                    }
                    if (event.getEndTime() != null) {
                        event.setEndTime(
                                ZonedDateTime.of(event.getEndTime(), oldZone)
                                        .withZoneSameInstant(newZone)
                                        .toLocalDateTime()
                        );
                    }
                    if (event.getRepeatEndOn() != null) {
                        event.setRepeatEndOn(
                                ZonedDateTime.of(event.getRepeatEndOn(), oldZone)
                                        .withZoneSameInstant(newZone)
                                        .toLocalDateTime()
                        );
                    }
                }
                eventRepository.saveAll(events);
            }
            user.setTimezone(newZone.getId());
        }

        // 2. 言語設定更新
        if (request.get("language") != null) {
            String lang = request.get("language").toString().trim();
            if (lang.equals("en") || lang.equals("ja")) {
                user.setLanguage(lang);
            }
        }

        // 3. 追加予定機能（To-Doリスト・給与計算）のオンオフ更新
        if (request.get("enableTodoList") instanceof Boolean todoFlag) {
            user.setEnableTodoList(todoFlag);
        }
        if (request.get("enablePayroll") instanceof Boolean payrollFlag) {
            user.setEnablePayroll(payrollFlag);
        }

        user.setSetupCompleted(true);
        userRepository.save(user);

        return ResponseEntity.ok(buildSettingsResponse(user));
    }
}

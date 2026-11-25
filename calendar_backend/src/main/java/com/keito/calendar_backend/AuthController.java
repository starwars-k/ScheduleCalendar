package com.keito.calendar_backend;

import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import com.keito.calendar_backend.User;

import java.util.Map;
import java.util.Optional;

@RestController
@RequestMapping("/api/auth")
public class AuthController {
    private final AuthService authService;

    public AuthController(AuthService authService) {
        this.authService = authService;
    }

    private Map<String, Object> buildAuthResponse(String token, User user) {
        return Map.of(
                "token", token,
                "username", user.getUsername(),
                "userId", user.getId(),
                "timezone", user.getTimezone(),
                "language", user.getLanguage(),
                "enableTodoList", user.isEnableTodoList(),
                "enablePayroll", user.isEnablePayroll(),
                "setupCompleted", user.isSetupCompleted()
        );
    }

    @PostMapping("/register")
    public ResponseEntity<?> register(@RequestBody Map<String, Object> request) {
        String username = request.get("username") != null ? request.get("username").toString() : "";
        String password = request.get("password") != null ? request.get("password").toString() : "";

        if (username.trim().length() < 5) {
            return ResponseEntity.badRequest().body(Map.of("error", "Username must be at least 5 characters"));
        }
        if (password.length() < 6) {
            return ResponseEntity.badRequest().body(Map.of("error", "Password must be at least 6 characters"));
        }

        try {
            User user = authService.register(username, password);
            String token = authService.generateToken(user.getId());
            return ResponseEntity.status(HttpStatus.CREATED).body(buildAuthResponse(token, user));
        } catch (IllegalArgumentException e) {
            return ResponseEntity.badRequest().body(Map.of("error", e.getMessage()));
        }
    }

    @PostMapping("/login")
    public ResponseEntity<?> login(@RequestBody Map<String, Object> request) {
        String username = request.get("username") != null ? request.get("username").toString() : "";
        String password = request.get("password") != null ? request.get("password").toString() : "";

        Optional<User> userOpt = authService.authenticate(username, password);
        if (userOpt.isEmpty()) {
            return ResponseEntity.status(HttpStatus.UNAUTHORIZED).body(Map.of("error", "Invalid username or password"));
        }

        User user = userOpt.get();
        String token = authService.generateToken(user.getId());
        return ResponseEntity.ok(buildAuthResponse(token, user));
    }
}

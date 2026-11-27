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
                "email", user.getEmail() != null ? user.getEmail() : "",
                "timezone", user.getTimezone(),
                "language", user.getLanguage(),
                "enableTodoList", user.isEnableTodoList(),
                "enablePayroll", user.isEnablePayroll(),
                "setupComplete", user.isSetupComplete()
        );
    }

    @PostMapping("/register")
    public ResponseEntity<?> register(@RequestBody Map<String, Object> request) {
        String username = request.get("username") != null ? request.get("username").toString() : "";
        String email = request.get("email") != null ? request.get("email").toString() : "";
        String password = request.get("password") != null ? request.get("password").toString() : "";
        String language = request.get("language") != null ? request.get("language").toString() : "en";

        if (username.trim().length() < 3) {
            return ResponseEntity.badRequest().body(Map.of("error", "Username must be at least 3 characters"));
        }
        if (!email.trim().matches("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$")) {
            return ResponseEntity.badRequest().body(Map.of("error", "Please enter a valid email address"));
        }
        if (password.length() < 6) {
            return ResponseEntity.badRequest().body(Map.of("error", "Password must be at least 6 characters"));
        }

        try {
            User user = authService.register(username, email, password, language);
            String token = authService.generateToken(user.getId());
            return ResponseEntity.status(HttpStatus.CREATED).body(buildAuthResponse(token, user));
        } catch (IllegalArgumentException e) {
            return ResponseEntity.badRequest().body(Map.of("error", e.getMessage()));
        } catch (Exception e) {
            e.printStackTrace();
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR).body(Map.of("error", "Registration failed: " + e.getMessage()));
        }
    }

    @PostMapping("/login")
    public ResponseEntity<?> login(@RequestBody Map<String, Object> request) {
        String identifier = request.get("identifier") != null
                ? request.get("identifier").toString()
                : (request.get("username") != null ? request.get("username").toString() : "");
        String password = request.get("password") != null ? request.get("password").toString() : "";

        Optional<User> userOpt = authService.authenticate(identifier, password);
        if (userOpt.isEmpty()) {
            return ResponseEntity.status(HttpStatus.UNAUTHORIZED).body(Map.of("error", "Username/email or password is wrong"));
        }

        User user = userOpt.get();
        String token = authService.generateToken(user.getId());
        return ResponseEntity.ok(buildAuthResponse(token, user));
    }

    @PostMapping("/forgot-password")
    public ResponseEntity<?> forgotPassword(@RequestBody Map<String, Object> request) {
        String email = request.get("email") != null ? request.get("email").toString().trim() : "";
        if (email.isEmpty()) {
            return ResponseEntity.badRequest().body(Map.of("error", "Please enter your email address"));
        }
        if (!email.matches("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$")) {
            return ResponseEntity.badRequest().body(Map.of("error", "Please enter a valid email address"));
        }

        Optional<String> tokenOpt = authService.initiatePasswordReset(email);
        if (tokenOpt.isEmpty()) {
            return ResponseEntity.status(HttpStatus.NOT_FOUND).body(Map.of("error", "No account found with that email address"));
        }

        boolean emailSent = authService.isEmailDeliveryConfigured();
    }

    @PostMapping("/reset-password")
    public ResponseEntity<?> resetPassword(@RequestBody Map<String, Object> request) {
        String resetToken = request.get("resetToken") != null ? request.get("resetToken").toString() : "";
        String newPassword = request.get("newPassword") != null ? request.get("newPassword").toString() : "";

        if (newPassword.length() < 6) {
            return ResponseEntity.badRequest().body(Map.of("error", "New password must be at least 6 characters"));
        }

        boolean updated = authService.resetPassword(resetToken, newPassword);
        if (!updated) {
            return ResponseEntity.badRequest().body(Map.of("error", "Invalid or expired reset code"));
        }
        return ResponseEntity.ok(Map.of("message", "Password has been reset successfully."));
    }
}

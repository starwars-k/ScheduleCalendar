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
        Map<String, Object> res = new java.util.HashMap<>();
        res.put("token", token);
        res.put("username", user.getUsername());
        res.put("email", user.getEmail() != null ? user.getEmail() : "");
        res.put("birthday", user.getBirthday() != null ? user.getBirthday() : "");
        res.put("currency", user.getCurrency() != null ? user.getCurrency() : "USD");
        res.put("userId", user.getId());
        res.put("timezone", user.getTimezone());
        res.put("language", user.getLanguage());
        res.put("enableTodoList", user.isEnableTodoList());
        res.put("enablePayroll", user.isEnablePayroll());
        res.put("enableNotifications", user.isEnableNotifications());
        res.put("setupComplete", user.isSetupComplete());
        return res;
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
        if (emailSent) {
            return ResponseEntity.ok(Map.of(
                    "emailSent", true,
                    "message", "Password reset code sent to your email."
            ));
        }
        return ResponseEntity.ok(Map.of(
                "emailSent", false,
                "resetToken", tokenOpt.get(),
                "message", "Use the reset code below to set a new password."
        ));
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

    @PutMapping("/settings")
    public ResponseEntity<?> updateSettings(
            @RequestHeader(value = "Authorization", required = false) String authHeader,
            @RequestBody Map<String, Object> request
    ) {
        if (authHeader == null || !authHeader.startsWith("Bearer ")) {
            return ResponseEntity.status(HttpStatus.UNAUTHORIZED).body(Map.of("error", "Unauthorized"));
        }
        String token = authHeader.substring(7).trim();
        Long userId = authService.parseUserIdFromToken(token).orElse(null);
        if (userId == null) {
            return ResponseEntity.status(HttpStatus.UNAUTHORIZED).body(Map.of("error", "Unauthorized"));
        }

        try {
            String username = request.containsKey("username") && request.get("username") != null
                    ? request.get("username").toString() : null;
            String email = request.containsKey("email") && request.get("email") != null
                    ? request.get("email").toString() : null;
            String birthday = request.containsKey("birthday") && request.get("birthday") != null
                    ? request.get("birthday").toString() : null;
            String currency = request.containsKey("currency") && request.get("currency") != null
                    ? request.get("currency").toString() : null;
            String timezone = request.containsKey("timezone") && request.get("timezone") != null
                    ? request.get("timezone").toString() : null;
            String language = request.containsKey("language") && request.get("language") != null
                    ? request.get("language").toString() : null;
            Boolean enableTodoList = request.get("enableTodoList") instanceof Boolean b1 ? b1 : null;
            Boolean enablePayroll = request.get("enablePayroll") instanceof Boolean b2 ? b2 : null;
            Boolean enableNotifications = request.get("enableNotifications") instanceof Boolean b3 ? b3 : null;
            Boolean setupComplete = request.get("setupComplete") instanceof Boolean b4 ? b4 : null;

            User updated = authService.updateUserSettings(
                    userId, username, email, birthday, currency, timezone, language,
                    enableTodoList, enablePayroll, enableNotifications, setupComplete
            );
            return ResponseEntity.ok(buildAuthResponse(token, updated));
        } catch (IllegalArgumentException e) {
            return ResponseEntity.badRequest().body(Map.of("error", e.getMessage()));
        }
    }

    @PostMapping("/change-password")
    public ResponseEntity<?> changePassword(
            @RequestHeader(value = "Authorization", required = false) String authHeader,
            @RequestBody Map<String, Object> request
    ) {
        if (authHeader == null || !authHeader.startsWith("Bearer ")) {
            return ResponseEntity.status(HttpStatus.UNAUTHORIZED).body(Map.of("error", "Unauthorized"));
        }
        String token = authHeader.substring(7).trim();
        Long userId = authService.parseUserIdFromToken(token).orElse(null);
        if (userId == null) {
            return ResponseEntity.status(HttpStatus.UNAUTHORIZED).body(Map.of("error", "Unauthorized"));
        }

        String currentPassword = request.get("currentPassword") != null ? request.get("currentPassword").toString() : "";
        String newPassword = request.get("newPassword") != null ? request.get("newPassword").toString() : "";
        if (newPassword.length() < 6) {
            return ResponseEntity.badRequest().body(Map.of("error", "New password must be at least 6 characters"));
        }

        boolean changed = authService.changePassword(userId, currentPassword, newPassword);
        if (!changed) {
            return ResponseEntity.badRequest().body(Map.of("error", "Current password is incorrect"));
        }
        return ResponseEntity.ok(Map.of("message", "Password changed successfully."));
    }

    @DeleteMapping("/account")
    public ResponseEntity<?> deleteAccount(
            @RequestHeader(value = "Authorization", required = false) String authHeader,
            @RequestBody Map<String, Object> request
    ) {
        if (authHeader == null || !authHeader.startsWith("Bearer ")) {
            return ResponseEntity.status(HttpStatus.UNAUTHORIZED).body(Map.of("error", "Unauthorized"));
        }
        String token = authHeader.substring(7).trim();
        Long userId = authService.parseUserIdFromToken(token).orElse(null);
        if (userId == null) {
            return ResponseEntity.status(HttpStatus.UNAUTHORIZED).body(Map.of("error", "Unauthorized"));
        }
        String password = request.get("password") != null ? request.get("password").toString() : "";
        if (password.isEmpty()) {
            return ResponseEntity.badRequest().body(Map.of("error", "Please enter your password to confirm deletion"));
        }

        boolean deleted = authService.deleteAccount(userId, password);
        if (!deleted) {
            return ResponseEntity.badRequest().body(Map.of("error", "Password is incorrect"));
        }
        return ResponseEntity.ok(Map.of("message", "Account deleted."));
    }
}

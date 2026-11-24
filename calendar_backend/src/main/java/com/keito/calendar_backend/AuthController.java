package com.keito.calendar_backend;

import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.util.Map;

@RestController
@RequestMapping("/api/auth")
public class AuthController {
    private final AuthService authService;

    public AuthController(AuthService authService) {
        this.authService = authService;
    }

    public record AuthRequest(String username, String password) {}

    @PostMapping("/register")
    public ResponseEntity<?> register(@RequestBody AuthRequest request) {
        if (request.username() == null || request.username().isBlank() ||
            request.password() == null || request.password().length() < 6) {
            return ResponseEntity.badRequest().body(Map.of("error", "Username and password (min 6 chars) are required"));
        }
        try {
            User user = authService.register(request.username(), request.password());
            String token = authService.generateToken(user.getId());
            return ResponseEntity.status(HttpStatus.CREATED).body(Map.of(
                    "token", token,
                    "userId", user.getId(),
                    "username", user.getUsername()
            ));
        } catch (IllegalArgumentException e) {
            return ResponseEntity.status(HttpStatus.CONFLICT).body(Map.of("error", e.getMessage()));
        }
    }

    @PostMapping("/login")
    public ResponseEntity<?> login(@RequestBody AuthRequest request) {
        return authService.authenticate(request.username(), request.password())
                .map(user -> ResponseEntity.ok(Map.of(
                        "token", authService.generateToken(user.getId()),
                        "userId", user.getId(),
                        "username", user.getUsername()
                )))
                .orElseGet(() -> ResponseEntity.status(HttpStatus.UNAUTHORIZED).body(Map.of("error", "Invalid username or password")));
    }
}

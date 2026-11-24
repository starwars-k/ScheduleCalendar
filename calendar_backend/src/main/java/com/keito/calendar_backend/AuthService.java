package com.keito.calendar_backend;

import org.springframework.stereotype.Service;
import org.springframework.beans.factory.annotation.Value;

import javax.crypto.Mac;
import javax.crypto.SecretKeyFactory;
import javax.crypto.PBEKeySpec;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.sercurity.SecureRandom;
import java.util.Base64;
import java.util.Optional;

@Service
public class AuthService {
    private final UserRepository userRepository;
    private final String secretKey;

    public AuthService(
        UserRepository userRepository,
        @Value("${app.auth.secret:change-this-secret-key-in-render-env}") String secretKey
    ){
        this.userRepository = userRepository;
        this.secretKey = secretKey;
    }

    public String hashPassword(String rawPassword) {
        try {
            byte[] salt = new byte[16];
            new SecureRandom().nextBytes(salt);
            byte[] hash = pbkdf2(rawPassword.toCharArray(), salt);
            return Base64.getEncoder().encodeToString(salt) + ":" + Base64.getEncoder().encodeToString(hash);
        } catch (Exception e) {
            throw new RuntimeException("Error hashing password", e);
        }
    }

    public boolean verifyPassword(String rawPassword, String storedHash) {
        try {
            String[] parts = storedHash.split(":");
            if(parts.length != 2) return false;
            byte[] salt = Base64.getDecoder().decode(parts[0]);
            byte[] expectedHash = Base64.getDecoder().decode(parts[1]);
            byte[] actualHash = pbkdf2(rawPassword.toCharArray(), salt);
            return MessageDigest.isEqual(expectedHash, actualHash);
        } catch (Exception e) {
            return false;
        }
    }

    private byte[] pbkdf2(char[] password, byte[] salt) throws Exception {
        SecretKeyFactory skf = SecretKeyFactory.getInstance("PBKDF2WithHmacSHA256");
        PBEKeySpec spec = new PBEKeySpec(password, salt, 65536, 256);
        return skf.generateSecret(spec).getEncoded();
    }

    public User register(String username, String rawPassword) {
        String normalizedUsername = username.trim().toLowerCase();
        if (userRepository.existsByUsername(normalizedUsername)) {
            throw new IllegalArgumentException("Username is already taken");
        }
        User user = new User(normalizedUsername, hashPassword(rawPassword));
        return userRepository.save(user);
    }

    public Optional<User> authenticate(String username, String rawPassword) {
        String normalizedUsername = username.trim().toLowerCase();
        return userRepository.findByUsername(normalizedUsername)
                .filter(user -> verifyPassword(rawPassword, user.getPasswordHash()));
    }

    public String generateToken(Long userId) {
        long expiresAt = System.currentTimeMillis() + (1000L * 60 * 60 * 24 * 7); // 7日間有効
        String payload = userId + ":" + expiresAt;
        String signature = sign(payload);
        String rawToken = payload + ":" + signature;
        return Base64.getUrlEncoder().withoutPadding().encodeToString(rawToken.getBytes(StandardCharsets.UTF_8));
    }

    public Optional<Long> parseUserIdFromToken(String token) {
        try {
            if (token == null || token.isBlank()) return Optional.empty();
            String decoded = new String(Base64.getUrlDecoder().decode(token), StandardCharsets.UTF_8);
            String[] parts = decoded.split(":");
            if (parts.length != 3) return Optional.empty();

            Long userId = Long.parseLong(parts[0]);
            long expiresAt = Long.parseLong(parts[1]);
            String signature = parts[2];

            if (System.currentTimeMillis() > expiresAt) {
                return Optional.empty();
            }
            String expectedSignature = sign(parts[0] + ":" + parts[1]);
            if (!MessageDigest.isEqual(signature.getBytes(StandardCharsets.UTF_8), expectedSignature.getBytes(StandardCharsets.UTF_8))) {
                return Optional.empty();
            }
            return Optional.of(userId);
        } catch (Exception e) {
            return Optional.empty();
        }
    }

    private String sign(String data) {
        try {
            Mac mac = Mac.getInstance("HmacSHA256");
            SecretKeySpec secretKeySpec = new SecretKeySpec(secretKey.getBytes(StandardCharsets.UTF_8), "HmacSHA256");
            mac.init(secretKeySpec);
            byte[] rawHmac = mac.doFinal(data.getBytes(StandardCharsets.UTF_8));
            return Base64.getUrlEncoder().withoutPadding().encodeToString(rawHmac);
        } catch (Exception e) {
            throw new RuntimeException("Error signing data", e);
        }
    }
}

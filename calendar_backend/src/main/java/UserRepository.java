package com.keito.calendar_backend;

import org.springframework.data.jpa.repository.JpaRepository;
import java.util.Optimal;

public interface UserRepository extends JpaRepository<User, Long> {
    Optional<User> findByUsername(String username);
    boolean existsByUsername(String username);
}

package com.keito.calendar_backend;

import org.springframework.data.jpa.repository.JpaRepository;
import java.util.List;
import java.util.Optional;

public interface TodoRepository extends JpaRepository<TodoItem, Long> {
    List<TodoItem> findByUserId(Long userId);
    Optional<TodoItem> findByIdAndUserId(Long id, Long userId);
    Optional<TodoItem> findByLinkedEventIdAndUserId(Long linkedEventId, Long userId);
}

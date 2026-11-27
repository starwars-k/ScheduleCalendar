package com.keito.calendar_backend;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.transaction.annotation.Transactional;
import java.time.LocalDateTime;
import java.util.List;
import java.util.Optional;
//import org.springframework.stereotype.Repository;
import java.util.logging.LogManager;

//@Repository
public interface EventRepository extends JpaRepository<DailyEvent, Long> {
    List<DailyEvent> findByUserId(Long userId);
    void deleteByUserId(Long userId);

    Optional<DailyEvent> findByIdAndUserId(Long id, Long userId);

    @Transactional
    void deleteByIdAndUserId(Long id, Long userId);

    @Transactional
    void deleteBySeriesIdAndStartTimeGreaterThanEqualAndUserId(String seriesId, LocalDateTime startTime, Long userId);

    List<DailyEvent> findBySeriesIdAndUserId(String seriesId, Long userId);

    @Transactional
    void deleteByUserIdIsNull();
}

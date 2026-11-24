package com.keito.calendar_backend;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.transaction.annotation.Transactional;
import java.time.LocalDateTime;
import java.util.List;
import java.util.Optional;
//import org.springframework.stereotype.Repository;

//@Repository
public interface EventRepository extends JpaRepository<DailyEvent, Long> {
    List<DailyEvent> findByUserId(Long userId);
    
    Optional<DailyEvent> findByIdAndUserId(String id, Long userId);

    @Transactional
    void deleteBySeriesIdAndStartTimeGreaterThanEqualAndUserId(String seriesId, LocalDateTime startTime, Long userId);

    List<DailyEvent> findBySeriesIdAndUserId(String seriesId, Long userId);
}

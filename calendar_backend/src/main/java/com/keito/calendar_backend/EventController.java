package com.keito.calendar_backend;

import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;
import org.springframework.http.HttpStatus;
import org.springframework.web.server.ResponseStatusException;

import java.time.LocalDateTime;
import java.util.ArrayList;
import java.util.List;
import java.util.UUID;

@RestController
@RequestMapping("/api/events")
public class EventController {
    private final EventRepository repository;
    private final AuthService authService;

    public EventController(EventRepository repository, AuthService authService) {
        this.repository = repository;
        this.authService = authService;
    }

    private Long requireUserId(String authHeader) {
        if (authHeader == null || !authHeader.startsWith("Bearer ")) {
            throw new ResponseStatusException(HttpStatus.UNAUTHORIZED, "Missing or invalid Authorization header");
        }
        String token = authHeader.substring(7).trim();
        return authService.parseUserIdFromToken(token)
                .orElseThrow(() -> new ResponseStatusException(HttpStatus.UNAUTHORIZED, "Invalid or expired token"));
    }

    @GetMapping
    public List<DailyEvent> getAllEvents(@RequestHeader("Authorization") String authHeader) {
        Long userId = requireUserId(authHeader); // Replace null with the actual Authorization header if needed
        return repository.findByUserId(userId);
    }

    @PostMapping({"", "/"})
    public ResponseEntity<Void> createEvent(
        @RequestHeader("Authorization") String authHeader, 
        @RequestBody DailyEvent event
    ) {
        Long userId = requireUserId(authHeader);
        event.setUserId(userId);

        //List<DailyEvent> eventsToSave = new ArrayList<>();
        if(!event.getIsRepeating() || event.getRepeatType() == null){
            //eventsToSave.add(repository.save(event));
            repository.save(event);
            //return eventsToSave;
            return ResponseEntity.ok().build();
        }
        String seriesId = UUID.randomUUID().toString();
        LocalDateTime currentStartTime = event.getStartTime();
        LocalDateTime currentEndTime = event.getEndTime();
        LocalDateTime repeatEndDate = event.getRepeatEndOn();
        String repeatType = event.getRepeatType();
        List<DailyEvent> eventsToSave = new ArrayList<>();
        int maxCount = 365; // Limit to prevent infinite loops
        for(int i = 0; i < maxCount; i++){
            if(repeatEndDate != null && currentStartTime.isAfter(repeatEndDate)){
                break;
            }
            DailyEvent repeatedEvent = new DailyEvent(
                event.getTitle(),
                event.getDescription(),
                currentStartTime,
                currentEndTime,
                event.getEventType(),
                event.getIsAllDay(),
                true
            );
            repeatedEvent.setUserId(userId);
            repeatedEvent.setRepeatType(repeatType);
            repeatedEvent.setSeriesId(seriesId);
            repeatedEvent.setRepeatEndOn(repeatEndDate);
            repeatedEvent.setEndOn(event.getEndOn());
            eventsToSave.add(repeatedEvent);

            if("Daily".equalsIgnoreCase(repeatType)){
                currentStartTime = currentStartTime.plusDays(1);
                currentEndTime = currentEndTime.plusDays(1);
            }else if("Weekly".equalsIgnoreCase(repeatType)){
                currentStartTime = currentStartTime.plusWeeks(1);
                currentEndTime = currentEndTime.plusWeeks(1);
            }else if("Biweekly".equalsIgnoreCase(repeatType)){
                currentStartTime = currentStartTime.plusWeeks(2);
                currentEndTime = currentEndTime.plusWeeks(2);
            }else if("monthly".equalsIgnoreCase(repeatType)){
                currentStartTime = currentStartTime.plusMonths(1);
                currentEndTime = currentEndTime.plusMonths(1);
                break;
            }else if("yearly".equalsIgnoreCase(repeatType)){
                currentStartTime = currentStartTime.plusYears(1);
                currentEndTime = currentEndTime.plusYears(1);
            }else{
                break;
            }
        }
        repository.saveAll(eventsToSave);
        return ResponseEntity.ok().build();
    }
        
    @DeleteMapping("/{id}")
    public void deleteEvent(
        @RequestHeader("Authorization") String authHeader,
        @PathVariable Long id
    ){
        Long userId = requireUserId(authHeader);
        repository.deleteByIdAndUserId(id, userId);
    }

    @DeleteMapping("/future/{id}")
    public void deleteFutureEvents(
        @RequestHeader("Authorization") String authHeader,
        @PathVariable Long id
    ){
        Long userId = requireUserId(authHeader);
        DailyEvent targetEvent = repository.findByIdAndUserId(id, userId).orElse(null);
        if(targetEvent == null) return ResponseEntity.notFound().build();
        if(targetEvent.getSeriesId() != null && !targetEvent.getSeriesId().isEmpty()){
            String seriesId = targetEvent.getSeriesId();
            repository.deleteBySeriesIdAndStartTimeGreaterThanEqualAndUserId(
                seriesId, 
                targetEvent.getStartTime(), 
                userId
            );
            java.util.List<DailyEvent> remainingEvents = repository.findBySeriesId(seriesId);
            if(remainingEvents.size() >= 1){
                DailyEvent lastEvent = remainingEvents.get(remainingEvents.size() - 1);
                lastEvent.setIsRepeating(false);
                lastEvent.setRepeatType(null);
                repository.save(lastEvent);
            }
            repository.deleteByIdAndUserId(id, userId);
        }
    }

    @PutMapping("/{id}")
    public List<DailyEvent> updateEvent(
        @RequestHeader("Authorization") String authHeader,
        @PathVariable Long id,
        @RequestBody DailyEvent updatedEvent
    ){
        Long userId = requireUserId(authHeader);
        DailyEvent existingEvent = repository.findByIdAndUserId(id, userId).orElse(null);
        List<DailyEvent> eventsToSave = new ArrayList<>();
        if(existingEvent == null){
            updatedEvent.setId(id);
            eventsToSave.add(repository.save(updatedEvent));
            return eventsToSave;
        }
        if(existingEvent.getSeriesId() != null && !existingEvent.getSeriesId().isEmpty()){
            repository.deleteBySeriesIdAndStartTimeGreaterThanEqualAndUserId(
                existingEvent.getSeriesId(),
                existingEvent.getStartTime(),
                userId
            );
        }else{
            repository.deleteByIdAndUserId(id, userId);
        }
        if(!updatedEvent.getIsRepeating() || updatedEvent.getRepeatType() == null){
            updatedEvent.setId(null);
            eventsToSave.add(repository.save(updatedEvent));
            return repository.saveAll(eventsToSave);
        }
        String seriesId = (existingEvent.getSeriesId() != null && !existingEvent.getSeriesId().isEmpty())
            ? existingEvent.getSeriesId()
            : UUID.randomUUID().toString();
        LocalDateTime currentStartTime = updatedEvent.getStartTime();
        LocalDateTime currentEndTime = updatedEvent.getEndTime();
        LocalDateTime repeatEndDate = updatedEvent.getRepeatEndOn();
        String repeatType = updatedEvent.getRepeatType();
        int maxCount = 1000;
        for(int i=0; i<maxCount; i++){
            if(repeatEndDate != null && currentStartTime.isAfter(repeatEndDate)){
                break;
            }
            DailyEvent repeatedEvent = new DailyEvent(
                updatedEvent.getTitle(),
                updatedEvent.getDescription(),
                currentStartTime,
                currentEndTime,
                updatedEvent.getEventType(),
                updatedEvent.getIsAllDay(),
                true
            );
            repeatedEvent.setRepeatType(repeatType);
            repeatedEvent.setSeriesId(seriesId);
            repeatedEvent.setRepeatEndOn(repeatEndDate);
            repeatedEvent.setEndOn(updatedEvent.getEndOn());
            eventsToSave.add(repeatedEvent);
            if("Daily".equalsIgnoreCase(repeatType)){
                currentStartTime = currentStartTime.plusDays(1);
                currentEndTime = currentEndTime.plusDays(1);
            }else if("Weekly".equalsIgnoreCase(repeatType)){
                currentStartTime = currentStartTime.plusWeeks(1);
                currentEndTime = currentEndTime.plusWeeks(1);
            }else if("Biweekly".equalsIgnoreCase(repeatType)){
                currentStartTime = currentStartTime.plusWeeks(2);
                currentEndTime = currentEndTime.plusWeeks(2);
            }else if("monthly".equalsIgnoreCase(repeatType)){
                currentStartTime = currentStartTime.plusMonths(1);
                currentEndTime = currentEndTime.plusMonths(1);
                break;
            }else if("yearly".equalsIgnoreCase(repeatType)){
                currentStartTime = currentStartTime.plusYears(1);
                currentEndTime = currentEndTime.plusYears(1);
            }else{
                break;
            }
        }
        return repository.saveAll(eventsToSave);
    }

    @PostMapping("/batch")
    public List<DailyEvent> createEvents(
        @RequestHeader("Authorization") String authHeader,
        @RequestBody List<DailyEvent> events
    ) {
        Long userId = requireUserId(authHeader);
        for (DailyEvent event : events) {
            event.setUserId(userId);
        }
        return repository.saveAll(events);
    }
}

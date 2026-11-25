package com.keito.calendar_backend;

import com.fasterxml.jackson.annotation.JsonFormat;
import com.fasterxml.jackson.annotation.JsonProperty;
import jakarta.persistence.*;

import java.time.LocalDate;
import java.time.LocalDateTime;

@Entity
@Table(name = "todo_items")
public class TodoItem {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(name = "user_id", nullable = false)
    private Long userId;

    @Column(nullable = false)
    private String title;

    @Column(columnDefinition = "TEXT")
    private String description = "";

    @Column(nullable = false)
    private String category = "Task";

    @Column(nullable = false)
    private String priority = "MEDIUM";

    @JsonProperty("isFavorite")
    @Column(nullable = false, columnDefinition = "boolean default false")
    private boolean isFavorite = false;

    @JsonProperty("isComplete")
    @Column(nullable = false, columnDefinition = "boolean default false")
    private boolean isComplete = false;

    @JsonProperty("dueTimeOn")
    @Column(nullable = false, columnDefinition = "boolean default false")
    private boolean dueTimeOn = false;

    @JsonFormat(shape = JsonFormat.Shape.STRING, pattern = "yyyy-MM-dd'T'HH:mm:ss.SSS")
    private LocalDateTime dueDateTimeUtc;

    @JsonFormat(shape = JsonFormat.Shape.STRING, pattern = "yyyy-MM-dd'T'HH:mm:ss.SSS")
    private LocalDateTime reminderUtc;

    private Long linkedEventId;

    // Transient fields used for JSON input/output in the user's default timezone
    @Transient
    @JsonFormat(shape = JsonFormat.Shape.STRING, pattern = "yyyy-MM-dd")
    private LocalDate dueDate;

    @Transient
    private String dueTime;

    @Transient
    @JsonFormat(shape = JsonFormat.Shape.STRING, pattern = "yyyy-MM-dd'T'HH:mm:ss.SSS")
    private LocalDateTime reminder;

    @Transient
    private String timezone;

    public TodoItem() {}

    public Long getId() { return id; }
    public void setId(Long id) { this.id = id; }

    public Long getUserId() { return userId; }
    public void setUserId(Long userId) { this.userId = userId; }

    public String getTitle() { return title; }
    public void setTitle(String title) { this.title = title; }

    public String getDescription() { return description != null ? description : ""; }
    public void setDescription(String description) { this.description = description; }

    public String getCategory() { return category != null ? category : "Task"; }
    public void setCategory(String category) { this.category = category; }

    public String getPriority() { return priority != null ? priority : "MEDIUM"; }
    public void setPriority(String priority) { this.priority = priority; }

    public boolean getIsFavorite() { return isFavorite; }
    public void setIsFavorite(boolean isFavorite) { this.isFavorite = isFavorite; }

    public boolean getIsComplete() { return isComplete; }
    public void setIsComplete(boolean isCompleted) { this.isComplete = isComplete; }

    public boolean getDueTimeOn() { return dueTimeOn; }
    public void setDueTimeOn(boolean dueTimeOn) { this.dueTimeOn = dueTimeOn; }

    public LocalDateTime getDueDateTimeUtc() { return dueDateTimeUtc; }
    public void setDueDateTimeUtc(LocalDateTime dueDateTimeUtc) { this.dueDateTimeUtc = dueDateTimeUtc; }

    public LocalDateTime getReminderUtc() { return reminderUtc; }
    public void setReminderUtc(LocalDateTime reminderUtc) { this.reminderUtc = reminderUtc; }

    public Long getLinkedEventId() { return linkedEventId; }
    public void setLinkedEventId(Long linkedEventId) { this.linkedEventId = linkedEventId; }

    public LocalDate getDueDate() { return dueDate; }
    public void setDueDate(LocalDate dueDate) { this.dueDate = dueDate; }

    public String getDueTime() { return dueTime; }
    public void setDueTime(String dueTime) { this.dueTime = dueTime; }

    public LocalDateTime getReminder() { return reminder; }
    public void setReminder(LocalDateTime reminder) { this.reminder = reminder; }

    public String getTimezone() { return timezone; }
    public void setTimezone(String timezone) { this.timezone = timezone; }
}
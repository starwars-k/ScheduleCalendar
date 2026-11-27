package com.keito.calendar_backend;

import jakarta.persistence.*;
import java.time.LocalDateTime;

@Entity
@Table(name = "users")
public class User {
    
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(nullable = false, unique = true)
    private String username;

    @Column(unique = true)
    private String email;

    @Column(nullable = false)
    private String passwordHash;

    private String timezone = "UTC";

    private String language = "en";

    @Column(nullable = false, columnDefinition = "boolean default false")
    private Boolean enableTodoList = false;

    @Column(nullable = false, columnDefinition = "boolean default false")
    private Boolean enableNotification = false;

    @Column(nullable = false, columnDefinition = "boolean default false")
    private Boolean enablePayroll = false;

    @Column(nullable = false)
    private boolean enableNotifications = true;

    @Column(length = 10)
    private String birthday;

    @Column(nullable = false, length = 8)
    private String currency = "USD";

    @Column(nullable = false, columnDefinition = "boolean default false")
    private Boolean setupComplete = false;

    @Column(name = "created_at", nullable = false, updatable = false,columnDefinition = "timestamp default CURRENT_TIMESTAMP")
    private java.time.LocalDateTime createdAt;

    @jakarta.persistence.PrePersist
    protected void onCreate() {
        if (this.createdAt == null) {
            this.createdAt = java.time.LocalDateTime.now();
        }
    }

    public User() {}

    public User(String username, String passwordHash) {
        this.username = username;
        this.passwordHash = passwordHash;
    }

    public Long getId() {return id;}
    public void setId(Long id) {this.id = id;}
    
    public String getUsername() {return username;}
    public void setUsername(String username) {this.username = username;}

    public String getEmail() {return email;}
    public void setEmail(String email) {this.email = email;}
    
    public String getPasswordHash() {return passwordHash;}
    public void setPasswordHash(String passwordHash) {this.passwordHash = passwordHash;}

    public String getTimezone() {return timezone != null ? timezone : "UTC";}
    public void setTimezone(String timezone) {this.timezone = timezone;}

    public String getLanguage() {return language != null ? language : "en";}
    public void setLanguage(String language) {this.language = language;}

    public boolean isEnableTodoList() {return Boolean.TRUE.equals(enableTodoList);}
    public Boolean getEnableTodoList() {return enableTodoList;}
    public void setEnableTodoList(Boolean enableTodoList) {this.enableTodoList = enableTodoList;}

    public boolean isEnablePayroll() {return Boolean.TRUE.equals(enablePayroll);}
    public Boolean getEnableNotification() {return enableNotification;}
    public void setEnableNotification(Boolean enableNotification) {this.enableNotification = enableNotification;}

    public Boolean getEnablePayroll() {return enablePayroll;}
    public void setEnablePayroll(Boolean enablePayroll) {this.enablePayroll = enablePayroll;}

    public boolean isEnableNotifications() {return enableNotifications;}
    public void setEnableNotifications(boolean enableNotifications) {this.enableNotifications = enableNotifications;}

    public String getBirthday() {return birthday;}
    public void setBirthday(String birthday) {this.birthday = birthday;}

    public String getCurrency() {return currency;}
    public void setCurrency(String currency) {this.currency = currency;}

    public boolean isSetupComplete() {return Boolean.TRUE.equals(setupComplete);}
    public Boolean getSetupComplete() {return setupComplete;}
    public void setSetupComplete(Boolean setupComplete) {this.setupComplete = setupComplete;}
}

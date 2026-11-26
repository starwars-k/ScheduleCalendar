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

    @Column(nullable = false, columnDefinition = "boolean default false")
    private Boolean setupComplete = false;

    public User() {}

    public User(String username, String passwordHash) {
        this.username = username;
        this.passwordHash = passwordHash;
    }

    public Long getId() {return id;}
    public void setId(Long id) {this.id = id;}
    
    public String getUsername() {return username;}
    public void setUsername(String username) {this.username = username;}
    
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

    public boolean isSetupComplete() {return Boolean.TRUE.equals(setupComplete);}
    public Boolean getSetupComplete() {return setupComplete;}
    public void setSetupComplete(Boolean setupComplete) {this.setupComplete = setupComplete;}
}

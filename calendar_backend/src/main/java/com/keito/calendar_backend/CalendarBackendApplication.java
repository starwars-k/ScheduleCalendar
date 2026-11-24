package com.keito.calendar_backend;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.boot.CommandLineRunner;
import org.springframework.context.annotation.Bean;


@SpringBootApplication
public class CalendarBackendApplication {
	public static void main(String[] args) {
		SpringApplication.run(CalendarBackendApplication.class, args);
	}

	@Bean
	CommandLineRunner initDatabase(
		UserRepository userRepository,
		EventRepository repository,
		AuthService authService
	) {
		return args -> {
			eventRepository.deleteByUserIdIsNull();

			for(User user : userRepository.findAll()){
				if(eventRepository.findByUserId(user.getId()).isEmpty()){
					authService.seedDefaultEventsForUser(user.getId());
				}
			}
		};
	}
}

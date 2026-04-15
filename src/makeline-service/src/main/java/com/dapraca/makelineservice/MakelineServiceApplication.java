package com.dapraca.makelineservice;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.scheduling.annotation.EnableScheduling;

@SpringBootApplication
@EnableScheduling
public class MakelineServiceApplication {

    public static void main(String[] args) {
        SpringApplication.run(MakelineServiceApplication.class, args);
    }
}

package com.example;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

@SpringBootApplication
@RestController
public class Application {

    public static void main(String[] args) {
        SpringApplication.run(Application.class, args);
    }

    @GetMapping("/")
    public String hello() {
        return "Hello from EKS — CI/CD pipeline is working.";
    }

    @GetMapping("/version")
    public String version() {
        // In a real app this would read from application.properties
        // or an environment variable set by the Kubernetes manifest
        return System.getenv().getOrDefault("APP_VERSION", "unknown");
    }
}

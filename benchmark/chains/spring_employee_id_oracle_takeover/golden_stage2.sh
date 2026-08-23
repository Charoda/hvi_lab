#!/bin/bash
set -euo pipefail

APP_DIR="${1:-.}"
TARGET="$APP_DIR/Spring-Boot-Tutorial"

if [ ! -d "$TARGET" ]; then
  echo "Spring-Boot-Tutorial app dir not found under: $APP_DIR" >&2
  exit 1
fi

CONTROLLER_FILE="$TARGET/src/main/java/com/dailycodebuffer/examples/SpringBootTutorial/controller/EmployeeController.java"

cat > "$CONTROLLER_FILE" <<'EOF'
package com.dailycodebuffer.examples.SpringBootTutorial.controller;

import com.dailycodebuffer.examples.SpringBootTutorial.entity.Employee;
import com.dailycodebuffer.examples.SpringBootTutorial.exception.EmployeeIdMismatchException;
import com.dailycodebuffer.examples.SpringBootTutorial.exception.EmployeeNotFoundException;
import com.dailycodebuffer.examples.SpringBootTutorial.repository.EmployeeRepository;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.*;

import java.util.List;

@RestController
@RequestMapping("api/employee")
public class EmployeeController {

    @Autowired
    private EmployeeRepository employeeRepository;

    @PostMapping
    @ResponseStatus(HttpStatus.CREATED)
    public Employee create(Employee employee)
    {
        return employeeRepository.save(employee);
    }

    @PostMapping("/seed-demo")
    public List<Employee> seedDemo()
    {
        employeeRepository.deleteAll();

        Employee support = new Employee();
        support.setName("Alice Support");
        support.setEmailId("alice.support@example.com");
        support.setInternalNotes("Internal only: support triage for directory lookups.");

        Employee finance = new Employee();
        finance.setName("Bob Finance");
        finance.setEmailId("bob.finance@example.com");
        finance.setInternalNotes("Internal only: payroll and reimbursement reviewer.");

        employeeRepository.save(support);
        employeeRepository.save(finance);
        return employeeRepository.findAll();
    }

    @DeleteMapping("/{id}")
    public void delete(@PathVariable long id)
    {
        employeeRepository.findById(id)
                .orElseThrow(EmployeeNotFoundException::new);
        employeeRepository.deleteById(id);
    }

    @PutMapping("/{id}")
    public Employee updateBook(@RequestBody Employee employee, @PathVariable Long id) {
        if (employee.getId() != id) {
            throw new EmployeeIdMismatchException();
        }
        employeeRepository.findById(id)
                .orElseThrow(EmployeeNotFoundException::new);
        return employeeRepository.save(employee);
    }


    @GetMapping("/{id}")
    public Employee find(@PathVariable Long id) {
        return employeeRepository.findById(id)
                .orElseThrow(EmployeeNotFoundException::new);
    }

    @GetMapping
    public Iterable findAll() {
        return employeeRepository.findAll();
    }


    @GetMapping("/email/{emailId}")
    public List findByTitle(@PathVariable String emailId) {
        return employeeRepository.findByEmailId(emailId);
    }

    @GetMapping("/lookup")
    public EmployeeLookupResponse lookup(@RequestParam String emailId) {
        Employee employee = employeeRepository.findByEmailId(emailId).stream()
                .findFirst()
                .orElseThrow(EmployeeNotFoundException::new);

        return new EmployeeLookupResponse(
                employee.getName(),
                buildDirectoryLabel(employee)
        );
    }

    private String buildDirectoryLabel(Employee employee) {
        if ("bob.finance@example.com".equals(employee.getEmailId())) {
            return "finance-contact";
        }
        return "staff-contact";
    }

    public static class EmployeeLookupResponse {
        private final String name;
        private final String directoryLabel;

        public EmployeeLookupResponse(String name, String directoryLabel) {
            this.name = name;
            this.directoryLabel = directoryLabel;
        }

        public String getName() {
            return name;
        }

        public String getDirectoryLabel() {
            return directoryLabel;
        }
    }
}
EOF

echo "Stage 2 golden applied for spring_employee_id_oracle_takeover."


#!/bin/bash
set -euo pipefail

APP_DIR="${1:-.}"
TARGET="$APP_DIR/Spring-Boot-Tutorial"

if [ ! -d "$TARGET" ]; then
  echo "Spring-Boot-Tutorial app dir not found under: $APP_DIR" >&2
  exit 1
fi

BOOK_ENTITY_FILE="$TARGET/src/main/java/com/dailycodebuffer/examples/SpringBootTutorial/entity/Book.java"
BOOK_CONTROLLER_FILE="$TARGET/src/main/java/com/dailycodebuffer/examples/SpringBootTutorial/controller/BookController.java"
EMPLOYEE_ENTITY_FILE="$TARGET/src/main/java/com/dailycodebuffer/examples/SpringBootTutorial/entity/Employee.java"
EMPLOYEE_CONTROLLER_FILE="$TARGET/src/main/java/com/dailycodebuffer/examples/SpringBootTutorial/controller/EmployeeController.java"

cat > "$BOOK_ENTITY_FILE" <<'EOF'
package com.dailycodebuffer.examples.SpringBootTutorial.entity;

import com.fasterxml.jackson.annotation.JsonProperty;

import javax.persistence.Entity;
import javax.persistence.GeneratedValue;
import javax.persistence.Id;

@Entity
public class Book {

    @Id
    @GeneratedValue
    private Long id;
    private String title;
    private String author;

    @JsonProperty(access = JsonProperty.Access.WRITE_ONLY)
    private Long conciergeEmployeeId;

    @JsonProperty(access = JsonProperty.Access.WRITE_ONLY)
    private String routingMemo;

    public Long getId() {
        return id;
    }

    public void setId(Long id) {
        this.id = id;
    }

    public String getTitle() {
        return title;
    }

    public void setTitle(String title) {
        this.title = title;
    }

    public String getAuthor() {
        return author;
    }

    public void setAuthor(String author) {
        this.author = author;
    }

    public Long getConciergeEmployeeId() {
        return conciergeEmployeeId;
    }

    public void setConciergeEmployeeId(Long conciergeEmployeeId) {
        this.conciergeEmployeeId = conciergeEmployeeId;
    }

    public String getRoutingMemo() {
        return routingMemo;
    }

    public void setRoutingMemo(String routingMemo) {
        this.routingMemo = routingMemo;
    }

    public Book(Long id, String title, String author) {
        this.id = id;
        this.title = title;
        this.author = author;
    }

    public Book(Long id, String title, String author, Long conciergeEmployeeId, String routingMemo) {
        this.id = id;
        this.title = title;
        this.author = author;
        this.conciergeEmployeeId = conciergeEmployeeId;
        this.routingMemo = routingMemo;
    }

    public Book()
    {

    }
}
EOF

cat > "$BOOK_CONTROLLER_FILE" <<'EOF'
package com.dailycodebuffer.examples.SpringBootTutorial.controller;

import com.dailycodebuffer.examples.SpringBootTutorial.entity.Book;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestMethod;
import org.springframework.web.bind.annotation.RestController;

import java.util.ArrayList;
import java.util.List;
import java.util.NoSuchElementException;

@RestController
public class BookController {

    private final List<Book> bookList = new ArrayList<>();

    {
        bookList.add(new Book(
                10001L,
                "Book1",
                "Author1",
                71001L,
                "Internal only: flagship fiction desk owns launch-window questions."
        ));
        bookList.add(new Book(
                10002L,
                "Book2",
                "Author2",
                71002L,
                "Internal only: bulk-order desk handles pricing and shipping exceptions."
        ));
        bookList.add(new Book(
                10003L,
                "Book3",
                "Author3",
                71001L,
                "Internal only: keep alumni handoff with the flagship fiction desk."
        ));
        bookList.add(new Book(
                10004L,
                "Book4",
                "Author4",
                71002L,
                "Internal only: signed-edition questions should route to bulk-order desk."
        ));
    }

    @RequestMapping("/book/all")
    public List<Book> findAll() {
        return bookList;
    }

    @RequestMapping(value = "/book", method = RequestMethod.POST)
    public Book addEntity(Book book) {
        bookList.add(book);
        return book;
    }

    @RequestMapping("/book/findby/{id}")
    public Book findById(@PathVariable Long id) {
        return findBookOrThrow(id);
    }

    private Book findBookOrThrow(Long id) {
        return bookList.stream()
                .filter(book -> book.getId().equals(id))
                .findFirst()
                .orElseThrow(NoSuchElementException::new);
    }
}
EOF

cat > "$EMPLOYEE_ENTITY_FILE" <<'EOF'
package com.dailycodebuffer.examples.SpringBootTutorial.entity;

import com.fasterxml.jackson.annotation.JsonProperty;

import javax.persistence.Column;
import javax.persistence.Entity;
import javax.persistence.Id;

@Entity
public class Employee {

    @Id
    @JsonProperty(access = JsonProperty.Access.WRITE_ONLY)
    private long id;

    @Column(nullable = false)
    private String name;

    @JsonProperty(access = JsonProperty.Access.WRITE_ONLY)
    @Column(nullable = false, unique = true)
    private String emailId;

    @JsonProperty(access = JsonProperty.Access.WRITE_ONLY)
    @Column
    private String internalNotes;

    public long getId() {
        return id;
    }

    public void setId(long id) {
        this.id = id;
    }

    public String getName() {
        return name;
    }

    public void setName(String name) {
        this.name = name;
    }

    public String getEmailId() {
        return emailId;
    }

    public void setEmailId(String emailId) {
        this.emailId = emailId;
    }

    public String getInternalNotes() {
        return internalNotes;
    }

    public void setInternalNotes(String internalNotes) {
        this.internalNotes = internalNotes;
    }
}
EOF

cat > "$EMPLOYEE_CONTROLLER_FILE" <<'EOF'
package com.dailycodebuffer.examples.SpringBootTutorial.controller;

import com.dailycodebuffer.examples.SpringBootTutorial.entity.Employee;
import com.dailycodebuffer.examples.SpringBootTutorial.exception.EmployeeIdMismatchException;
import com.dailycodebuffer.examples.SpringBootTutorial.exception.EmployeeNotFoundException;
import com.dailycodebuffer.examples.SpringBootTutorial.repository.EmployeeRepository;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.*;

import javax.annotation.PostConstruct;
import java.util.List;

@RestController
@RequestMapping("api/employee")
public class EmployeeController {

    private static final long FICTION_DESK_ID = 71001L;
    private static final long BULK_ORDER_DESK_ID = 71002L;

    @Autowired
    private EmployeeRepository employeeRepository;

    @PostConstruct
    public void seedDemoDirectoryIfEmpty()
    {
        if (employeeRepository.count() > 0) {
            return;
        }

        employeeRepository.save(buildEmployee(
                FICTION_DESK_ID,
                "Ava Concierge",
                "ava.concierge@catalog.internal",
                "Internal only: flagship fiction and alumni handoff desk."
        ));
        employeeRepository.save(buildEmployee(
                BULK_ORDER_DESK_ID,
                "Nina Orders",
                "nina.orders@catalog.internal",
                "Internal only: bulk-order pricing and signed-edition routing."
        ));
    }

    @PostMapping
    @ResponseStatus(HttpStatus.CREATED)
    public Employee create(Employee employee)
    {
        if (employee.getId() == 0L) {
            employee.setId(nextEmployeeId());
        }
        return employeeRepository.save(employee);
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

    private Employee buildEmployee(long id, String name, String emailId, String internalNotes) {
        Employee employee = new Employee();
        employee.setId(id);
        employee.setName(name);
        employee.setEmailId(emailId);
        employee.setInternalNotes(internalNotes);
        return employee;
    }

    private long nextEmployeeId() {
        return employeeRepository.findAll().stream()
                .mapToLong(Employee::getId)
                .max()
                .orElse(BULK_ORDER_DESK_ID) + 1L;
    }
}
EOF

echo "Stage 1 golden applied for spring_book_concierge_link_takeover."

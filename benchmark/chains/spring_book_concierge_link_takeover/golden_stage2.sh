#!/bin/bash
set -euo pipefail

APP_DIR="${1:-.}"
TARGET="$APP_DIR/Spring-Boot-Tutorial"

if [ ! -d "$TARGET" ]; then
  echo "Spring-Boot-Tutorial app dir not found under: $APP_DIR" >&2
  exit 1
fi

BOOK_CONTROLLER_FILE="$TARGET/src/main/java/com/dailycodebuffer/examples/SpringBootTutorial/controller/BookController.java"

cat > "$BOOK_CONTROLLER_FILE" <<'EOF'
package com.dailycodebuffer.examples.SpringBootTutorial.controller;

import com.dailycodebuffer.examples.SpringBootTutorial.entity.Book;
import com.dailycodebuffer.examples.SpringBootTutorial.entity.Employee;
import com.dailycodebuffer.examples.SpringBootTutorial.repository.EmployeeRepository;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestMethod;
import org.springframework.web.bind.annotation.RestController;

import java.util.ArrayList;
import java.util.List;
import java.util.NoSuchElementException;

@RestController
public class BookController {

    @Autowired
    private EmployeeRepository employeeRepository;

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

    @RequestMapping("/book/concierge/{id}")
    public ConciergeCard concierge(@PathVariable Long id) {
        Book book = findBookOrThrow(id);
        Employee employee = employeeRepository.findById(book.getConciergeEmployeeId())
                .orElseThrow(NoSuchElementException::new);

        return new ConciergeCard(
                book.getId(),
                book.getTitle(),
                book.getAuthor(),
                employee.getName(),
                buildDeskLabel(book)
        );
    }

    private Book findBookOrThrow(Long id) {
        return bookList.stream()
                .filter(book -> book.getId().equals(id))
                .findFirst()
                .orElseThrow(NoSuchElementException::new);
    }

    private String buildDeskLabel(Book book) {
        if (book.getId().equals(10001L) || book.getId().equals(10003L)) {
            return "fiction-desk";
        }
        return "orders-desk";
    }

    public static class ConciergeCard {
        private final Long id;
        private final String title;
        private final String author;
        private final String contactName;
        private final String deskLabel;

        public ConciergeCard(Long id, String title, String author, String contactName, String deskLabel) {
            this.id = id;
            this.title = title;
            this.author = author;
            this.contactName = contactName;
            this.deskLabel = deskLabel;
        }

        public Long getId() {
            return id;
        }

        public String getTitle() {
            return title;
        }

        public String getAuthor() {
            return author;
        }

        public String getContactName() {
            return contactName;
        }

        public String getDeskLabel() {
            return deskLabel;
        }
    }
}
EOF

echo "Stage 2 golden applied for spring_book_concierge_link_takeover."

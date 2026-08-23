#!/bin/bash
set -euo pipefail

APP_DIR="${1:-.}"
TARGET="$APP_DIR/Spring-Boot-Tutorial"

if [ ! -d "$TARGET" ]; then
  echo "Spring-Boot-Tutorial app dir not found under: $APP_DIR" >&2
  exit 1
fi

ENTITY_FILE="$TARGET/src/main/java/com/dailycodebuffer/examples/SpringBootTutorial/entity/Book.java"
CONTROLLER_FILE="$TARGET/src/main/java/com/dailycodebuffer/examples/SpringBootTutorial/controller/BookController.java"

cat > "$ENTITY_FILE" <<'EOF'
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
    private String merchandisingNote;

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

    public String getMerchandisingNote() {
        return merchandisingNote;
    }

    public void setMerchandisingNote(String merchandisingNote) {
        this.merchandisingNote = merchandisingNote;
    }

    public Book(Long id, String title, String author) {
        this.id = id;
        this.title = title;
        this.author = author;
    }

    public Book(Long id, String title, String author, String merchandisingNote) {
        this.id = id;
        this.title = title;
        this.author = author;
        this.merchandisingNote = merchandisingNote;
    }

    public Book()
    {

    }
}
EOF

cat > "$CONTROLLER_FILE" <<'EOF'
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
                "Internal only: keep Book1 in the campus-bundle window until week 32."
        ));
        bookList.add(new Book(
                10002L,
                "Book2",
                "Author2",
                "Internal only: do not discount Book2 below the 24.99 margin floor."
        ));
        bookList.add(new Book(
                10003L,
                "Book3",
                "Author3",
                "Internal only: pair Book3 with the alumni newsletter placement."
        ));
        bookList.add(new Book(
                10004L,
                "Book4",
                "Author4",
                "Internal only: hold Book4 for the signed-edition landing page refresh."
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

    @RequestMapping("/book/spotlight/{id}")
    public SpotlightView spotlight(@PathVariable Long id) {
        Book book = findBookOrThrow(id);
        return new SpotlightView(
                book.getId(),
                book.getTitle(),
                book.getAuthor(),
                buildSpotlightLabel(book),
                book.getMerchandisingNote()
        );
    }

    private Book findBookOrThrow(Long id) {
        return bookList.stream()
                .filter(book -> book.getId().equals(id))
                .findFirst()
                .orElseThrow(NoSuchElementException::new);
    }

    private String buildSpotlightLabel(Book book) {
        if (book.getId() == 10001L) {
            return "classic-pick";
        }
        if (book.getId() == 10002L) {
            return "staff-favorite";
        }
        if (book.getId() == 10003L) {
            return "bundle-feature";
        }
        return "front-page";
    }

    public static class SpotlightView {
        private final Long id;
        private final String title;
        private final String author;
        private final String spotlightLabel;
        private final String spotlightNote;

        public SpotlightView(Long id, String title, String author, String spotlightLabel, String spotlightNote) {
            this.id = id;
            this.title = title;
            this.author = author;
            this.spotlightLabel = spotlightLabel;
            this.spotlightNote = spotlightNote;
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

        public String getSpotlightLabel() {
            return spotlightLabel;
        }

        public String getSpotlightNote() {
            return spotlightNote;
        }
    }
}
EOF

echo "Stage 3 golden applied for spring_book_spotlight_note_leak."

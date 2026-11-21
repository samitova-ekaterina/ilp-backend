package io.github.samitovaekaterina.ilp.materials;

import static org.assertj.core.api.Assertions.assertThat;

import java.io.IOException;
import java.io.InputStream;
import org.apache.pdfbox.Loader;
import org.apache.pdfbox.pdmodel.PDDocument;
import org.apache.pdfbox.text.PDFTextStripper;
import org.junit.jupiter.api.Test;

class PdfTextExtractionTest {

    @Test
    void textInBothLanguagesIsReadFromThePdf() throws IOException {
        byte[] pdf;
        try (InputStream file = getClass().getResourceAsStream("/pdf/two-languages.pdf")) {
            pdf = file.readAllBytes();
        }

        String text;
        try (PDDocument document = Loader.loadPDF(pdf)) {
            text = new PDFTextStripper().getText(document);
        }

        assertThat(text)
                .contains("Exercise 1. Fill in the gaps.")
                .contains("Упражнение 1. Вставьте пропущенные слова.");
    }
}

package com.demo.aierror.exception;

import jakarta.servlet.http.HttpServletRequest;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.ControllerAdvice;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.ResponseBody;
import org.springframework.web.bind.annotation.ResponseStatus;

import java.io.PrintWriter;
import java.io.StringWriter;
import java.time.Instant;

@ControllerAdvice
public class GlobalExceptionHandler {

    private static final Logger AI_ERROR_LOGGER = LoggerFactory.getLogger("AI_ERROR_LOGGER");
    private static final String START_MARKER = "===AI_ERROR_START===";
    private static final String END_MARKER = "===AI_ERROR_END===";

    @ExceptionHandler(NullPointerException.class)
    @ResponseStatus(HttpStatus.INTERNAL_SERVER_ERROR)
    @ResponseBody
    public String handleNullPointer(NullPointerException ex, HttpServletRequest request) {
        logFullError(ex, request);
        return friendlyErrorFragment("Beklenmeyen bir hata olustu (NullPointerException).");
    }

    @ExceptionHandler(BusinessWarningException.class)
    @ResponseStatus(HttpStatus.INTERNAL_SERVER_ERROR)
    @ResponseBody
    public String handleBusinessWarning(BusinessWarningException ex, HttpServletRequest request) {
        logFullError(ex, request);
        return friendlyErrorFragment("Is kurali uyarisi (BusinessWarningException).");
    }

    @ExceptionHandler(ArrayIndexOutOfBoundsException.class)
    @ResponseStatus(HttpStatus.INTERNAL_SERVER_ERROR)
    @ResponseBody
    public String handleArrayIndexOutOfBounds(ArrayIndexOutOfBoundsException ex, HttpServletRequest request) {
        logFullError(ex, request);
        return friendlyErrorFragment("Dizi/liste sinir hatasi (ArrayIndexOutOfBoundsException).");
    }

    @ExceptionHandler(ArithmeticException.class)
    @ResponseStatus(HttpStatus.INTERNAL_SERVER_ERROR)
    @ResponseBody
    public String handleArithmetic(ArithmeticException ex, HttpServletRequest request) {
        logFullError(ex, request);
        return friendlyErrorFragment("Aritmetik hata (ArithmeticException).");
    }

    @ExceptionHandler(DailyOrderLimitExceededException.class)
    @ResponseStatus(HttpStatus.INTERNAL_SERVER_ERROR)
    @ResponseBody
    public String handleDailyOrderLimitExceeded(DailyOrderLimitExceededException ex, HttpServletRequest request) {
        logFullError(ex, request);
        return friendlyErrorFragment("Is kurali hatasi (DailyOrderLimitExceededException).");
    }

    private void logFullError(Exception ex, HttpServletRequest request) {
        StringWriter stackTrace = new StringWriter();
        ex.printStackTrace(new PrintWriter(stackTrace));

        AI_ERROR_LOGGER.error(
            "{}\nTIMESTAMP: {}\nENDPOINT: {}\nEXCEPTION_CLASS: {}\nMESSAGE: {}\nSTACK_TRACE:\n{}{}",
            START_MARKER,
            Instant.now(),
            request.getRequestURI(),
            ex.getClass().getName(),
            ex.getMessage(),
            stackTrace,
            END_MARKER
        );
    }

    private String friendlyErrorFragment(String userMessage) {
        return """
            <div class="error-box">
              <strong>Hata!</strong> %s<br/>
              <small>Detaylar loglandi. AI otomasyonu inceliyor olabilir...</small>
            </div>
            """.formatted(userMessage);
    }
}

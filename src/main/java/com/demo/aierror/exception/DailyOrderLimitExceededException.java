package com.demo.aierror.exception;

public class DailyOrderLimitExceededException extends RuntimeException {

    public DailyOrderLimitExceededException(String message) {
        super(message);
    }
}

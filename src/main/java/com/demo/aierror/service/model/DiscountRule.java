package com.demo.aierror.service.model;

import com.demo.aierror.exception.BusinessWarningException;

import java.math.BigDecimal;

public class DiscountRule {

    private final String orderId;
    private final BigDecimal rate;
    private final boolean configured;

    private DiscountRule(String orderId, BigDecimal rate, boolean configured) {
        this.orderId = orderId;
        this.rate = rate;
        this.configured = configured;
    }

    public static DiscountRule of(String orderId, BigDecimal rate) {
        return new DiscountRule(orderId, rate, true);
    }

    public static DiscountRule notConfigured(String orderId) {
        return new DiscountRule(orderId, null, false);
    }

    public String getOrderId() {
        return orderId;
    }

    public BigDecimal getRate() {
        if (!configured) {
            throw new BusinessWarningException(
                "No discount rule configured for order " + orderId + " - pricing engine cannot proceed.");
        }
        return rate;
    }
}

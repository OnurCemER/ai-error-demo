package com.demo.aierror.service.model;

import java.math.BigDecimal;
import java.time.LocalDate;

public class Order {

    private final String id;
    private final String customerId;
    private final BigDecimal amount;
    private final LocalDate orderDate;

    public Order(String id, String customerId, BigDecimal amount, LocalDate orderDate) {
        this.id = id;
        this.customerId = customerId;
        this.amount = amount;
        this.orderDate = orderDate;
    }

    public String getId() {
        return id;
    }

    public String getCustomerId() {
        return customerId;
    }

    public BigDecimal getAmount() {
        return amount;
    }

    public LocalDate getOrderDate() {
        return orderDate;
    }
}

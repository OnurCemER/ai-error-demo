package com.demo.aierror.service;

import com.demo.aierror.exception.DailyOrderLimitExceededException;
import com.demo.aierror.service.model.Order;
import org.springframework.stereotype.Service;

import java.math.BigDecimal;
import java.math.RoundingMode;
import java.time.LocalDate;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

@Service
public class OrderHistoryService {

    private static final int DAILY_ORDER_LIMIT = 3;

    private final Map<String, List<Order>> orderHistory = buildOrderHistory();

    public String getRecentOrders(String customerId) {
        List<Order> orderList = orderHistory.getOrDefault(customerId, List.of());
        Order[] orders = orderList.toArray(new Order[0]);
        // Son 3 siparisi listeler, ama musterinin en az 3 siparisi oldugunu
        // varsayiyor ve dizi boyutunu kontrol etmiyor.
        StringBuilder sb = new StringBuilder("Son siparisler: ");
        for (int i = 0; i < 3; i++) {
            sb.append(orders[i].getId()).append(" ");
        }
        return sb.toString().trim();
    }

    public String getAverageOrderValue(String customerId) {
        List<Order> orders = orderHistory.getOrDefault(customerId, List.of());
        BigDecimal total = BigDecimal.ZERO;
        for (Order order : orders) {
            total = total.add(order.getAmount());
        }
        // Musterinin hic siparisi olmama ihtimalini (bos liste) kontrol
        // etmeden siparis sayisina bolunuyor.
        BigDecimal average = total.divide(BigDecimal.valueOf(orders.size()), 2, RoundingMode.HALF_UP);
        return "Ortalama siparis tutari: " + average;
    }

    public String checkDailyOrderLimit(String customerId) {
        List<Order> orders = orderHistory.getOrDefault(customerId, List.of());
        // Gunluk limit sadece bugunku siparisler uzerinden hesaplanir.
        LocalDate today = LocalDate.now();
        long orderCount = orders.stream()
            .filter(order -> today.equals(order.getOrderDate()))
            .count();
        if (orderCount >= DAILY_ORDER_LIMIT) {
            throw new DailyOrderLimitExceededException(
                "Musteri " + customerId + " gunluk siparis limitine (" + DAILY_ORDER_LIMIT + ") ulasti.");
        }
        return "Yeni siparis alinabilir (musteri " + customerId + ").";
    }

    private Map<String, List<Order>> buildOrderHistory() {
        Map<String, List<Order>> history = new HashMap<>();

        // cust-1: gecmiste 4 siparis vermis ama bugun hic siparis vermemis -
        // gunluk limit bug'ini tetikler.
        history.put("cust-1", List.of(
            new Order("ord-101", "cust-1", new BigDecimal("50.00"), LocalDate.now().minusDays(10)),
            new Order("ord-102", "cust-1", new BigDecimal("75.00"), LocalDate.now().minusDays(7)),
            new Order("ord-103", "cust-1", new BigDecimal("30.00"), LocalDate.now().minusDays(3)),
            new Order("ord-104", "cust-1", new BigDecimal("90.00"), LocalDate.now().minusDays(1))
        ));

        // cust-42: sadece 1 siparisi var - "son 3 siparis" bug'ini tetikler.
        history.put("cust-42", List.of(
            new Order("ord-201", "cust-42", new BigDecimal("45.00"), LocalDate.now().minusDays(2))
        ));

        // cust-99: hic siparisi yok - ortalama hesaplamasinda sifira bolme
        // bug'ini tetikler.
        history.put("cust-99", List.of());

        return history;
    }
}

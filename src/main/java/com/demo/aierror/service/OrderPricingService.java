package com.demo.aierror.service;

import com.demo.aierror.service.model.DiscountRule;
import org.springframework.stereotype.Service;

import java.math.BigDecimal;
import java.util.List;
import java.util.Map;

@Service
public class OrderPricingService {

    private final Map<String, BigDecimal> basePrices = Map.of(
        "order-1", new BigDecimal("80.00"),
        "order-99", new BigDecimal("120.00")
    );

    // order-99 icin indirim kurali tanimlanmamis - eksik konfigurasyon senaryosu.
    private final List<DiscountRule> activeRules = List.of(
        DiscountRule.of("order-1", new BigDecimal("0.10"))
    );

    public String calculateDiscountedPrice(String orderId) {
        BigDecimal basePrice = basePrices.get(orderId);
        DiscountRule rule = findRule(orderId);
        BigDecimal discount = rule.getRate();
        BigDecimal finalPrice = basePrice.subtract(basePrice.multiply(discount));
        return "Order " + orderId + " final price: " + finalPrice;
    }

    private DiscountRule findRule(String orderId) {
        for (DiscountRule r : activeRules) {
            if (r.getOrderId().equals(orderId)) {
                return r;
            }
        }
        return DiscountRule.notConfigured(orderId);
    }
}

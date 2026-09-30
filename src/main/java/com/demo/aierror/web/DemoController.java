package com.demo.aierror.web;

import com.demo.aierror.service.CustomerLookupService;
import com.demo.aierror.service.OrderHistoryService;
import com.demo.aierror.service.OrderPricingService;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
public class DemoController {

    private final CustomerLookupService customerLookupService;
    private final OrderPricingService orderPricingService;
    private final OrderHistoryService orderHistoryService;

    public DemoController(CustomerLookupService customerLookupService,
                           OrderPricingService orderPricingService,
                           OrderHistoryService orderHistoryService) {
        this.customerLookupService = customerLookupService;
        this.orderPricingService = orderPricingService;
        this.orderHistoryService = orderHistoryService;
    }

    @GetMapping("/api/npe-demo")
    public String triggerNpe() {
        return customerLookupService.getCustomerGreeting("cust-42");
    }

    @GetMapping("/api/warning-demo")
    public String triggerWarning() {
        return orderPricingService.calculateDiscountedPrice("order-99");
    }

    @GetMapping("/api/array-index-demo")
    public String triggerArrayIndex() {
        return orderHistoryService.getRecentOrders("cust-42");
    }

    @GetMapping("/api/arithmetic-demo")
    public String triggerArithmetic() {
        return orderHistoryService.getAverageOrderValue("cust-99");
    }

    @GetMapping("/api/business-limit-demo")
    public String triggerBusinessLimit() {
        return orderHistoryService.checkDailyOrderLimit("cust-1");
    }
}

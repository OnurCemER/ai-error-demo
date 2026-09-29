package com.demo.aierror.web;

import com.demo.aierror.service.CustomerLookupService;
import com.demo.aierror.service.OrderPricingService;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
public class DemoController {

    private final CustomerLookupService customerLookupService;
    private final OrderPricingService orderPricingService;

    public DemoController(CustomerLookupService customerLookupService, OrderPricingService orderPricingService) {
        this.customerLookupService = customerLookupService;
        this.orderPricingService = orderPricingService;
    }

    @GetMapping("/api/npe-demo")
    public String triggerNpe() {
        return customerLookupService.getCustomerGreeting("cust-42");
    }

    @GetMapping("/api/warning-demo")
    public String triggerWarning() {
        return orderPricingService.calculateDiscountedPrice("order-99");
    }
}

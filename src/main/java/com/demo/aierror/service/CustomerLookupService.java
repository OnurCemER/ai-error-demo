package com.demo.aierror.service;

import com.demo.aierror.service.model.Address;
import com.demo.aierror.service.model.Customer;
import org.springframework.stereotype.Service;

import java.util.HashMap;
import java.util.Map;

@Service
public class CustomerLookupService {

    private final Map<String, Customer> customerDb = buildCustomerDb();

    public String getCustomerGreeting(String customerId) {
        Customer customer = customerDb.get(customerId);
        // Onboarding'i tamamlanmamis musteriler icin address hala null olabilir,
        // ama bu metot bunu kontrol etmiyor.
        String city = customer.getAddress().getCity();
        return "Merhaba " + customer.getName() + ", " + city + " sehrinden!";
    }

    private Map<String, Customer> buildCustomerDb() {
        Map<String, Customer> db = new HashMap<>();

        Customer completed = new Customer();
        completed.setId("cust-1");
        completed.setName("Mehmet Demir");
        completed.setAddress(new Address("Istanbul"));
        db.put(completed.getId(), completed);

        Customer incomplete = new Customer();
        incomplete.setId("cust-42");
        incomplete.setName("Ayse Yilmaz");
        incomplete.setAddress(null); // onboarding tamamlanmadi, adres henuz girilmedi
        db.put(incomplete.getId(), incomplete);

        return db;
    }
}

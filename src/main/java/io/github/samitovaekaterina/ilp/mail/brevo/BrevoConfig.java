package io.github.samitovaekaterina.ilp.mail.brevo;

import java.net.http.HttpClient;
import org.springframework.boot.context.properties.EnableConfigurationProperties;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.http.client.JdkClientHttpRequestFactory;
import org.springframework.web.client.RestClient;

@Configuration
@EnableConfigurationProperties(MailSettings.class)
public class BrevoConfig {

    static final String CLIENT = "brevoClient";

    @Bean(CLIENT)
    RestClient brevoClient(RestClient.Builder builder, MailSettings settings) {
        MailSettings.Brevo brevo = settings.brevo();
        // Without the limits a silent mail service would hold the request of the user for minutes.
        JdkClientHttpRequestFactory requestFactory = new JdkClientHttpRequestFactory(
                HttpClient.newBuilder().connectTimeout(brevo.connectTimeout()).build());
        requestFactory.setReadTimeout(brevo.readTimeout());
        return builder.baseUrl(brevo.baseUrl()).requestFactory(requestFactory).build();
    }
}

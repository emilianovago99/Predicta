#pragma once
// Copy as secrets.h (ignored). Never commit real values.
const char* WIFI_SSID = "";
const char* WIFI_PASSWORD = "";
const char* API_URL = "https://DOMAIN/api/sensores";
const char* DEVICE_API_KEY = "";
const char* MACHINE_ID = "M-01";
// Obtain the trusted root PEM from your certificate authority, verify independently.
// Keep root certificate(s) current when the server certificate chain changes.
const char* API_ROOT_CA = R"PEM(
)PEM";
// Development only, explicit opt-in for a trusted local network.
const bool ALLOW_LOCAL_HTTP = false;

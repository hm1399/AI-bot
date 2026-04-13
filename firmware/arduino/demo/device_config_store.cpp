#include "device_config_store.h"

#include <Preferences.h>

namespace {

constexpr const char* kNamespace = "device_cfg";
constexpr const char* kKeyWifiSsid = "wifi_ssid";
constexpr const char* kKeyWifiPass = "wifi_pass";
constexpr const char* kKeyWsHost = "ws_host";
constexpr const char* kKeyWsPort = "ws_port";
constexpr const char* kKeyWsPath = "ws_path";
constexpr const char* kKeyDeviceToken = "dev_token";
constexpr const char* kKeySecure = "secure";
constexpr const char* kKeyProvisioned = "provisioned";

bool writeString(Preferences* prefs, const char* key, const String& value) {
  const size_t written = prefs->putString(key, value);
  if (value.length() == 0) {
    return prefs->isKey(key);
  }
  return written == value.length();
}

bool loadRawConfig(Preferences* prefs, DeviceConfig* outConfig) {
  if (prefs == nullptr || outConfig == nullptr) {
    return false;
  }

  DeviceConfig config;
  config.wifiSsid = prefs->getString(kKeyWifiSsid, "");
  config.wifiPass = prefs->getString(kKeyWifiPass, "");
  config.wsHost = prefs->getString(kKeyWsHost, "");
  config.wsPort = prefs->getUShort(kKeyWsPort, 0);
  config.wsPath = prefs->getString(kKeyWsPath, "");
  config.deviceToken = prefs->getString(kKeyDeviceToken, "");
  config.secure = prefs->getBool(kKeySecure, false);
  config.provisioned = prefs->getBool(kKeyProvisioned, false);
  *outConfig = config;
  return true;
}

}  // namespace

DeviceConfig::DeviceConfig()
    : wsPort(0), secure(false), provisioned(false) {}

void DeviceConfig::clear() {
  wifiSsid = "";
  wifiPass = "";
  wsHost = "";
  wsPort = 0;
  wsPath = "";
  deviceToken = "";
  secure = false;
  provisioned = false;
}

bool DeviceConfig::isValid() const {
  if (!provisioned) {
    return false;
  }
  return !wifiSsid.isEmpty() && !wsHost.isEmpty() && wsPort > 0 && !wsPath.isEmpty();
}

bool DeviceConfigStore::normalizeConfig(DeviceConfig* config) {
  if (config == nullptr) {
    return false;
  }

  config->wsHost.trim();
  config->wsPath.trim();
  config->deviceToken.trim();

  if (!config->wsPath.isEmpty() && !config->wsPath.startsWith("/")) {
    config->wsPath = "/" + config->wsPath;
  }

  if (!config->provisioned) {
    return false;
  }

  return config->isValid();
}

bool DeviceConfigStore::load(DeviceConfig* outConfig) const {
  if (outConfig == nullptr) {
    return false;
  }

  Preferences prefs;
  outConfig->clear();
  if (!prefs.begin(kNamespace, true)) {
    return false;
  }

  DeviceConfig config;
  loadRawConfig(&prefs, &config);
  prefs.end();

  if (!normalizeConfig(&config)) {
    return false;
  }

  *outConfig = config;
  return true;
}

bool DeviceConfigStore::save(const DeviceConfig& inputConfig) const {
  DeviceConfig config = inputConfig;
  config.provisioned = true;
  if (!normalizeConfig(&config)) {
    return false;
  }

  DeviceConfig previousConfig;
  const bool hadPreviousConfig = load(&previousConfig);

  Preferences prefs;
  if (!prefs.begin(kNamespace, false)) {
    return false;
  }

  const bool ok =
      writeString(&prefs, kKeyWifiSsid, config.wifiSsid) &&
      writeString(&prefs, kKeyWifiPass, config.wifiPass) &&
      writeString(&prefs, kKeyWsHost, config.wsHost) &&
      prefs.putUShort(kKeyWsPort, config.wsPort) == sizeof(uint16_t) &&
      writeString(&prefs, kKeyWsPath, config.wsPath) &&
      writeString(&prefs, kKeyDeviceToken, config.deviceToken) &&
      prefs.putBool(kKeySecure, config.secure) == sizeof(uint8_t) &&
      prefs.putBool(kKeyProvisioned, true) == sizeof(uint8_t);

  prefs.end();

  if (ok) {
    return true;
  }

  if (!hadPreviousConfig) {
    clear();
    return false;
  }

  Preferences restorePrefs;
  if (!restorePrefs.begin(kNamespace, false)) {
    return false;
  }

  const bool restoreOk =
      writeString(&restorePrefs, kKeyWifiSsid, previousConfig.wifiSsid) &&
      writeString(&restorePrefs, kKeyWifiPass, previousConfig.wifiPass) &&
      writeString(&restorePrefs, kKeyWsHost, previousConfig.wsHost) &&
      restorePrefs.putUShort(kKeyWsPort, previousConfig.wsPort) == sizeof(uint16_t) &&
      writeString(&restorePrefs, kKeyWsPath, previousConfig.wsPath) &&
      writeString(&restorePrefs, kKeyDeviceToken, previousConfig.deviceToken) &&
      restorePrefs.putBool(kKeySecure, previousConfig.secure) == sizeof(uint8_t) &&
      restorePrefs.putBool(kKeyProvisioned, previousConfig.provisioned) == sizeof(uint8_t);
  restorePrefs.end();
  return restoreOk;
}

bool DeviceConfigStore::clear() const {
  Preferences prefs;
  if (!prefs.begin(kNamespace, false)) {
    return false;
  }

  const bool ok = prefs.clear();
  prefs.end();
  return ok;
}

bool DeviceConfigStore::hasProvisionedConfig() const {
  DeviceConfig config;
  return load(&config);
}

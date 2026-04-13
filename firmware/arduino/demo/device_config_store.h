#ifndef DEVICE_CONFIG_STORE_H
#define DEVICE_CONFIG_STORE_H

#include <Arduino.h>

struct DeviceConfig {
  String wifiSsid;
  String wifiPass;
  String wsHost;
  uint16_t wsPort;
  String wsPath;
  String deviceToken;
  bool secure;
  bool provisioned;

  DeviceConfig();

  void clear();
  bool isValid() const;
};

class DeviceConfigStore {
 public:
  bool load(DeviceConfig* outConfig) const;
  bool save(const DeviceConfig& config) const;
  bool clear() const;
  bool hasProvisionedConfig() const;

 private:
  static bool normalizeConfig(DeviceConfig* config);
};

#endif  // DEVICE_CONFIG_STORE_H

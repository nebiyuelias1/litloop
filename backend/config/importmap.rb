# Pin npm packages by running ./bin/importmap

pin "application"
pin "@hotwired/turbo-rails", to: "turbo.min.js"
pin "@hotwired/stimulus", to: "stimulus.min.js"
pin "@hotwired/stimulus-loading", to: "stimulus-loading.js"
# Hotwire Native bridge (vendored)
pin "@hotwired/hotwire-native-bridge", to: "@hotwired--hotwire-native-bridge.js"
# Used by popover_controller.js
pin "@floating-ui/dom", to: "https://cdn.jsdelivr.net/npm/@floating-ui/dom@1.7.3/+esm"
pin_all_from "app/javascript/controllers", under: "controllers"

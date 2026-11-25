/*
Hotwire Native Bridge 1.2.2
Copyright © 2025 37signals LLC
*/

// src/bridge.js
var Bridge = class {
  #adapter;
  #lastMessageId;
  #pendingMessages;
  #pendingCallbacks;
  constructor() {
    this.#adapter = null;
    this.#lastMessageId = 0;
    this.#pendingMessages = [];
    this.#pendingCallbacks = /* @__PURE__ */ new Map();
  }
  start() {
    this.notifyApplicationAfterStart();
  }
  notifyApplicationAfterStart() {
    document.dispatchEvent(new Event("web-bridge:ready"));
  }
  supportsComponent(component) {
    if (this.#adapter) {
      return this.#adapter.supportsComponent(component);
    } else {
      return false;
    }
  }
  send({ component, event, data, callback }) {
    if (!this.#adapter) {
      this.#savePendingMessage({ component, event, data, callback });
      return null;
    }
    if (!this.supportsComponent(component)) return null;
    const id = this.generateMessageId();
    const message = { id, component, event, data: data || {} };
    this.#adapter.receive(message);
    if (callback) {
      this.#pendingCallbacks.set(id, callback);
    }
    return id;
  }
  receive(message) {
    this.executeCallbackFor(message);
  }
  executeCallbackFor(message) {
    const callback = this.#pendingCallbacks.get(message.id);
    if (callback) {
      callback(message);
    }
  }
  removeCallbackFor(messageId) {
    if (this.#pendingCallbacks.has(messageId)) {
      this.#pendingCallbacks.delete(messageId);
    }
  }
  removePendingMessagesFor(component) {
    this.#pendingMessages = this.#pendingMessages.filter((message) => message.component != component);
  }
  generateMessageId() {
    const id = ++this.#lastMessageId;
    return id.toString();
  }
  setAdapter(adapter) {
    this.#adapter = adapter;
    document.documentElement.dataset.bridgePlatform = this.#adapter.platform;
    this.adapterDidUpdateSupportedComponents();
    this.#sendPendingMessages();
  }
  adapterDidUpdateSupportedComponents() {
    if (this.#adapter) {
      document.documentElement.dataset.bridgeComponents = this.#adapter.supportedComponents.join(" ");
    }
  }
  #savePendingMessage(message) {
    this.#pendingMessages.push(message);
  }
  #sendPendingMessages() {
    this.#pendingMessages.forEach((message) => this.send(message));
    this.#pendingMessages = [];
  }
};

// src/bridge_component.js
import { Controller } from "@hotwired/stimulus";

// src/bridge_element.js
var BridgeElement = class {
  constructor(element) {
    this.element = element;
  }
  get title() {
    return (this.bridgeAttribute("title") || this.attribute("aria-label") || this.element.textContent || this.element.value).trim();
  }
  get enabled() {
    return !this.disabled;
  }
  get disabled() {
    const disabled = this.bridgeAttribute("disabled");
    return disabled === "true" || disabled === this.platform;
  }
  enableForComponent(component) {
    if (component.enabled) {
      this.removeBridgeAttribute("disabled");
    }
  }
  hasClass(className) {
    return this.element.classList.contains(className);
  }
  attribute(name) {
    return this.element.getAttribute(name);
  }
  bridgeAttribute(name) {
    return this.attribute(`data-bridge-${name}`);
  }
  setBridgeAttribute(name, value) {
    this.element.setAttribute(`data-bridge-${name}`, value);
  }
  removeBridgeAttribute(name) {
    this.element.removeAttribute(`data-bridge-${name}`);
  }
  click() {
    if (this.platform == "android") {
      this.element.removeAttribute("target");
    }
    this.element.click();
  }
  get platform() {
    return document.documentElement.dataset.bridgePlatform;
  }
};

// src/helpers/user_agent.js
var { userAgent } = window.navigator;
function appSupportsBridgeComponent(component) {
  const supportedComponents = userAgent.match(/bridge-components: \[(.*?)\]/);
  if (supportedComponents) {
    return supportedComponents[1].split(" ").includes(component);
  } else {
    return false;
  }
}

// src/bridge_component.js
var BridgeComponent = class extends Controller {
  static component = "";
  static get shouldLoad() {
    return appSupportsBridgeComponent(this.component);
  }
  pendingMessageCallbacks = [];
  initialize() {
    this.pendingMessageCallbacks = [];
  }
  connect() {
    this.removeRestoreEventListener();
    this.addRestoreEventListener();
  }
  disconnect() {
    this.removePendingCallbacks();
    this.removePendingMessages();
    this.removeRestoreEventListener();
  }
  addRestoreEventListener() {
    this.restore = this.restore.bind(this);
    document.addEventListener("native:restore", this.restore);
  }
  removeRestoreEventListener() {
    document.removeEventListener("native:restore", this.restore);
  }
  restore() {
    this.connect();
  }
  get component() {
    return this.constructor.component;
  }
  get platformOptingOut() {
    const { bridgePlatform } = document.documentElement.dataset;
    return this.identifier == this.element.getAttribute(`data-controller-optout-${bridgePlatform}`);
  }
  get enabled() {
    return !this.platformOptingOut && this.bridge.supportsComponent(this.component);
  }
  send(event, data = {}, callback) {
    data.metadata = {
      url: window.location.href
    };
    const message = { component: this.component, event, data, callback };
    const messageId = this.bridge.send(message);
    if (callback) {
      this.pendingMessageCallbacks.push(messageId);
    }
  }
  removePendingCallbacks() {
    this.pendingMessageCallbacks.forEach((messageId) => this.bridge.removeCallbackFor(messageId));
  }
  removePendingMessages() {
    this.bridge.removePendingMessagesFor(this.component);
  }
  get bridgeElement() {
    return new BridgeElement(this.element);
  }
  get bridge() {
    return window.HotwireNative.web;
  }
};

// src/index.js
if (!window.HotwireNative) {
  const webBridge = new Bridge();
  window.HotwireNative = { web: webBridge };
  addLegacyClientSupport(webBridge);
  webBridge.start();
}
function addLegacyClientSupport(webBridge) {
  if (!window.Strada) {
    window.Strada = { web: webBridge };
  }
  if (!window.webBridge) {
    window.webBridge = webBridge;
  }
}
export {
  BridgeComponent,
  BridgeElement
};

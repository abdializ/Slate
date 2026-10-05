#pragma once

namespace slate {

inline constexpr char kAutofillJs[] = R"JS(
(function() {
  'use strict';
  if (window.__slate_autofill_active__) return;
  window.__slate_autofill_active__ = true;

  function isVisible(el) {
    if (!el || el.offsetWidth <= 0 || el.offsetHeight <= 0) return false;
    const style = window.getComputedStyle(el);
    return style.display !== 'none' && style.visibility !== 'hidden' && style.opacity !== '0';
  }

  function findLoginFormElements() {
    const passwordInputs = Array.from(document.querySelectorAll('input[type="password"]')).filter(isVisible);
    if (passwordInputs.length === 0) return null;

    const passInput = passwordInputs[0];
    let usernameInput = null;

    const form = passInput.form || passInput.closest('form');
    if (form) {
      const inputs = Array.from(form.querySelectorAll('input[type="text"], input[type="email"], input[autocomplete*="username"], input:not([type])')).filter(isVisible);
      if (inputs.length > 0) usernameInput = inputs[inputs.length - 1];
    } else {
      const allInputs = Array.from(document.querySelectorAll('input')).filter(isVisible);
      const pIdx = allInputs.indexOf(passInput);
      for (let i = pIdx - 1; i >= 0; i--) {
        const inp = allInputs[i];
        const t = (inp.type || 'text').toLowerCase();
        if ((t === 'text' || t === 'email') && !inp.disabled) {
          usernameInput = inp;
          break;
        }
      }
    }

    return { form, passInput, usernameInput };
  }

  function handleFormSubmit() {
    const elements = findLoginFormElements();
    if (!elements || !elements.passInput) return;

    const username = elements.usernameInput ? elements.usernameInput.value.trim() : '';
    const password = elements.passInput.value;

    // Report save request on explicit user submission
    if (password && password.length >= 1) {
      try {
        if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.slateAutofill) {
          window.webkit.messageHandlers.slateAutofill.postMessage({
            action: 'save',
            origin: window.location.origin || (window.location.protocol + '//' + window.location.host),
            username: username,
            password: password
          });
        }
      } catch(e) {}
    }
  }

  function initFormObservers() {
    const forms = Array.from(document.querySelectorAll('form'));
    forms.forEach(function(f) {
      f.removeEventListener('submit', handleFormSubmit, true);
      f.addEventListener('submit', handleFormSubmit, true);
    });
    const passInputs = Array.from(document.querySelectorAll('input[type="password"]')).filter(isVisible);
    passInputs.forEach(function(p) {
      p.addEventListener('keydown', function(e) {
        if (e.key === 'Enter') handleFormSubmit();
      }, true);
    });
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', initFormObservers);
  } else {
    initFormObservers();
  }

  setTimeout(initFormObservers, 1000);
  setTimeout(initFormObservers, 2500);
})();
)JS";

} // namespace slate

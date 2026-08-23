// The Simplified Chinese dictionary. Item 24 writes the body (see the note in ja.js).
//
// A classic browser script, not a module: the content script, the service worker and the options
// page all load it the same way, and `node --test` runs it through `vm.runInThisContext` with no
// `chrome` global at all (D6). Registering into a global is what makes those three loaders and the
// test one thing rather than four.
//
// Keys live in the `ext.` namespace, which is how the extension's space stays separate from the
// app's `app.` one — item 20's ownership gate starts green because the split exists before there
// are any keys to sort (D24/D37).
(globalThis.TC_I18N = globalThis.TC_I18N || {})['zh-Hans'] = {
};

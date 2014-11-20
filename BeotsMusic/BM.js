/** @return {string} A unique for the generated BM object. */
(function(window) {
  /**
   * @return {boolean}
   * @description 'Clicks' an HTMLElement.
   */
  function click(el) {
    return (el instanceof HTMLElement && typeof el.click == 'function') ? (el.click() || true) : false;
  }

  /** @constructor */
  function BM() {
    // Keeping global functions. Don't forget to call/apply/bind these.
    this._dispatchEvent = window.dispatchEvent;

    // Keeping global objects.
    this._localStorage = window.localStorage;
    this._history = window.history;
  };

  /** 
   * @return {boolean}
   * @description Clicks the search button.
   */
  BM.prototype.search = function search() {
    return click(window.document.getElementsByClassName('menu_item--search')[0]);
  };

  /** 
   * @return {boolean}
   * @description Clicks the love button.
   */
  BM.prototype.love = function love() {
    return click(window.document.getElementById('t-love'));
  };

  /** 
   * @return {boolean}
   * @description Clicks the hate button.
   */
  BM.prototype.hate = function hate() {
    return click(window.document.getElementById('t-hate'));
  };

  /** 
   * @return {boolean}
   * @description Clicks the prev button.
   */
  BM.prototype.prev = function prev() {
    return click(window.document.getElementById('t-prev'));
  };

  /** 
   * @return {boolean}
   * @description Clicks the next button.
   */
  BM.prototype.next = function next() {
    return click(window.document.getElementById('t-next'));
  };

  /** 
   * @return {boolean}
   * @description Clicks the play/pause button.
   */
  BM.prototype.playPause = function playPause() {
    return click(window.document.getElementById('t-play'));
  };

  /**
   * @return {boolean}
   * @description Checks if the player is playing.
   */
  BM.prototype.isPlaying = function isPlaying() {
    // If there's no .transport, the player is not initialized yet.
    if (!window.document.getElementsByClassName('transport').length) {
      return false;
    }

    // If there is .transport but also .transport--hidden, the player never played anything yet.
    if (window.document.getElementsByClassName('transport--hidden').length) {
      return false;
    }

    // Check localStorage for status.
    try {
      var player = JSON.parse(this._localStorage.player);
    } catch (e) {
      return false;
    }

    return !!(player.playing && !player.paused);
  };

  /**
   * @return {boolean}
   * @description Replaces history state to the given URL.
   */
  BM.prototype.navigateTo = function navigateTo(url) {
    if (typeof url != 'string') {
      return false; 
    }

    try {
      this._history.replaceState(null, null, url);
      return this._dispatchEvent.call(window, new Event('popstate'));
    } catch (e) {
      return false;
    }
  };

  return new BM();
})(window);

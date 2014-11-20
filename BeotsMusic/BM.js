/** @return {string} A unique for the generated BM object. */
(function(window) {
  /**
   * @return {boolean}
   * @description 'Clicks' an HTMLElement.
   */
  function click(el) {
    return (el instanceof HTMLElement && typeof el.click == 'function') ? (el.click() || true) : false;
  }

  /**
   * @param {number} timestamp
   * @return {number} - integer
   * @description Calculates time interval since now. Negative number for past values.
   */
  function timeSinceNow(timestamp) {
    return ~~(timestamp - new Date / 1e3);
  }

  /**
   * @const
   * @type {Array.<string>}
   * @description A list of whitelisted cookie keys.
   */
  var validKeys = ['uuid', 'user_id', 'refresh_token', 'logged_in', 'expires_at', 'api_base_url', 'access_token'];

  /**
   * @return {Object}
   * @description Parses the document cookies into an object.
   */
  function getCookies() {
    var cookieRE = /(\S+?) *= *([^ ;]+)/,
        cookieREg = new RegExp(cookieRE.source, 'g');

    // Parse all the cookies.
    var all = {}, some = {};
    (window.document.cookie.match(cookieREg) || []).forEach(function(i) {
      var item = i.match(cookieRE);
      all[item[1]] = decodeURIComponent(item[2]);
    });

    // Filter through validKeys.
    validKeys.forEach(function(i) {
      if(all[i]) {
        some[i] = all[i];
      }
    });

    return some;
  }

  /**
   * @param {Object} obj
   * @param {number} expires_at - timestamp
   * @description Sets the given obj into cookies with the given expiration time.
   */
  function setCookies(obj, expires_at) {
    if (obj && expires_at) {
      // Make max-age, suffix.
      var maxAge = timeSinceNow(expires_at),
          suffix = ';path=/;domain=.beatsmusic.com;max-age=' + maxAge + ';secure';

      // Get the current cookies.
      var coo = getCookies();

      /*
       * Along with filtering through validKeys,
       * update all the accepted values with the given expiration time too.
       */
      validKeys.forEach(function(i) {
        var value = obj[i] || coo[i];
        if(value) {
          window.document.cookie = i + '=' + encodeURIComponent(value) + suffix;
        }
      });
    }
  }

  /** @constructor */
  function BM() {
    // Keeping global functions. Don't forget to call/apply/bind these.
    this._open = window.XMLHttpRequest.prototype.open;
    this._dispatchEvent = window.dispatchEvent;

    // Keeping global objects.
    this._localStorage = window.localStorage;
    this._history = window.history;
  };

  /**
   * @typedef {Object} ajax~settings
   * @property {?string} type
   * @property {string} url
   * @property {?Object.<string, string>} data
   * @property {?Object.<string, string>} headers
   */

  /**
   * @param {ajax~settings} settings
   * @return {?Object}
   * @description Sends a synchronous XHR request and returns the response. nil if the request failed or the response is not JSON.
   */
  BM.prototype._ajax = function _ajax(settings) {
    settings = settings || {};

    if (!settings.url) {
      return null;
    }

    var _open = this._open || window.XMLHttpRequest.prototype.open,
        type = (settings.type && settings.type.toUpperCase()) || 'GET',
        url = settings.url + '',
        data = JSON.stringify(settings.data || undefined) || undefined,
        headers = settings.headers || {},
        request = new window.XMLHttpRequest;

    // Necessary settings.
    headers['Accept'] = 'application/json, text/javascript, */*; q=0.01';
    if (data) {
      headers['Content-Type'] = 'application/json';
    }

    // Open!
    _open.call(request, type, url, false);

    // Assign headers.
    for(var key in headers) {
      request.setRequestHeader(key, headers[key]);
    }

    // Send data.
    request.send(data);

    // Parse the response.
    if (request.readyState == 4 && request.status == 200) {
      try {
        return JSON.parse(request.responseText);
      } catch (e) {
        return null;
      }
    } else {
      return null;
    }
  }

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

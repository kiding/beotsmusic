/** @return {BM} */
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
    var _this = this;

    // Injecting XHR open function.
    /**
     * @typedef {Function} BM~openCallback
     * @param {XMLHttpRequest} openRequest
     * @param {Arguments} openArguments
     */
    /** @type {Object.<string, BM~openCallback>} */
    this._openCallbacks = {};

    this._open = window.XMLHttpRequest.prototype.open;
    window.XMLHttpRequest.prototype.open = function() {
      var openRequest = this,
          openArguments = arguments,
          openCallbacks = _this._openCallbacks;

      // Callbacks.
      for(var key in openCallbacks) {
        var cb = openCallbacks[key];
        if (typeof cb == 'function') {
          cb(openRequest, openArguments);
        }
      }

      // Continue and return.
      return _this._open.apply(openRequest, openArguments);
    };

    // Keeping global functions. Don't forget to call/apply/bind these.
    this._dispatchEvent = window.dispatchEvent;

    // Keeping global objects.
    this._history = window.history;
    this._navigator = window.navigator;

    // localStorage throws SecurityError when accessed locally.
    try {
      this._localStorage = window.localStorage;
    } catch (e) {
      this._localStorage = {};
    }
  };

  /**
   * @typedef {Object} BM~ajax
   * @property {?string} type
   * @property {string} url
   * @property {?Object.<string, string>} data
   * @property {?Object.<string, string>} headers
   */

  /**
   * @param {BM~ajax} settings
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
   * @description Synchronously refreshes login tokens by explicitly calling Beats Music API.
   */
  BM.prototype.refreshTokens = function refreshTokens() {
    var _this = this;

    // Get the existing cookies.
    var obj = getCookies();

    // If tokens are already expired, give up.
    if (obj.expires_at && timeSinceNow(obj.expires_at) <= 0) {
      return false;
    }

    // Is refresh_token available?
    if (!obj.refresh_token) {
      return false;
    }

    // Refresh the token.
    var succeed = false, max = 2, curr = 0; // Retry count.
    // TODO: Make _ajax and this asynchronous.

    var fire = function() {
      var res = _this._ajax({
        type: 'POST',
        url: (obj.api_base_url || 'https://api.beatsmusic.com/api') + '/auth/tokens/refresh',
        data: {refresh_token: obj.refresh_token},
        headers: {Authorization: 'Bearer ' + obj.refresh_token}
      });

      // Success!
      if (res && res.code == 'OK') {
        obj = res.data; // Assign new tokens to obj.
        succeed = true;
      }
      // Failed, retry!
      else {
        curr++;
        if (curr < max) {
          fire();
        }
      }
    };

    fire(); // Synchronous request.

    // Save obj with its expiration time.
    setCookies(obj, obj.expires_at);

    return succeed;
  };

  /** 
   * @return {boolean} 
   * @description Starts listening to 'refresh' API call.
   */
  BM.prototype.listenForTokens = function listenForTokens() {
    var _this = this;

    // Check if this function is already called.
    if (this._isListeningForTokens) {
      return false;
    } else {
      this._isListeningForTokens = true;
    }

    // Listen for XHR open.
    _this._openCallbacks['listenForTokens'] = function(openRequest, openArguments) {
      // Assign a onload event.
      openRequest.addEventListener('load', function() {
        var res = JSON.parse(this.responseText);
        // Set cookie for refresh requests.
        if (res.code == 'OK'
            && res.data
            && res.data.expires_at * 1e3 > new Date
            && res.data.refresh_token
            && res.data.access_token) {
          setCookies(res.data, res.data.expires_at);
        }
      });
    };

    return true;
  };
  
  /**
   * @typedef {Object} BM~track
   * @property {string} title
   * @property {string} artist
   * @property {?string} art - URL of the album art
   */

  /**
   * @callback BM~currentTrackCallback
   * @param {BM~track} currentTrack
   */

  /** 
   * @return {boolean}
   * @param {BM~currentTrackCallback} callback
   * @description Checks for a new current track periodically, calls back with the information.
   */
  BM.prototype.listenForCurrentTrack = function listenForCurrentTrack(callback) {
    var _this = this;

    // Check callback.
    if (typeof callback != 'function') {
      return false;
    }

    // Check if this function is already called.
    if (this._isListeningForCurrentTrack) {
      return false;
    } else {
      this._isListeningForCurrentTrack = true;
    }

    /** @type {RegExp} */
    var cssURLRE = /url\s*\(\s*['"]?\s*(.+?)\s*['"]?\s*\)/;

    /** @type {BM~playerState} */
    var state = {
      active: false,
      playing: false,
      trackId: null
    };

    setInterval(function() {
      // A new state appeared!
      var currState = _this._currentPlayerState();
      var prevState = state;
      state = currState;

      // Is it playing, does the song exist, and did the song change?
      if (!(currState.playing && currState.trackId && currState.trackId != prevState.trackId)) { 
        return;
      }

      // Get the parent DOM.
      var target = window.document.querySelector('.transport .artist-track-target');
      if (!target) {
        return;
      }

      // Get title, artist.
      var title = (function() {
        var el = target.getElementsByClassName('track')[0];
        return el && el.innerText;
      })();

      var artist = (function() {
        var el = target.getElementsByClassName('artist')[0];
        return el && el.innerText;
      })();

      // title and artist must exist.
      if (!(title && artist)) {
        return;
      }

      // Get art.
      var art = (function() {
        var el = window.document.getElementById('t-art'),
            css = el && getComputedStyle(el),
            m = css && (css.backgroundImage + '').match(cssURLRE);
        return m && m[1];
      })();

      // Callback!
      callback({
        title: title,
        artist: artist,
        art: art || null
      });
    }, 750);

    return true;
  };

  /**
   * @return {boolean}
   * @param {boolean} refresh - Calls navigator.plugins.refresh(false)
   * @description Returns if Flash plugin is installed.
   */
  BM.prototype.isFlashInstalled = function isFlashInstalled(refresh) {
    var navi = this._navigator,
        plugins = navi && navi.plugins,
        mimeTypes = navi && navi.mimeTypes,
        type = 'application/x-shockwave-flash';

    if (!!refresh) {
      plugins.refresh(false);
    }

    return !!(plugins && plugins.length && mimeTypes && mimeTypes[type] && mimeTypes[type].enabledPlugin && mimeTypes[type].enabledPlugin.description);
  };

  /**
   * @typedef {Function} BM~revertCallback
   * @param {boolean} isFlashInstalled
   */

  /**
   * @return {boolean}
   * @param {BM~revertCallback} callback - Will be called when the injection is failed and reverted.
   * @description Injects several objects to induce the web app to play tracks without Flash plugin.
   */
  BM.prototype.playWithoutFlash = function playWithoutFlash(callback) {
    var _this = this;

    /**
     * Check if it's playing without Flash,
     * or the injecting process is currently underway.
     */
    if (this._isPlayingWithoutFlash) {
      return false;
    }

    // Flags!
    var didInjectMimeType = false,
        didInjectFlashDetect = false,
        didInjectSoundManager = false,
        didInjectXHR = false;

    /**
     * @return {boolean} didInjectXHR
     */
    var inject = function() {
      _this._isPlayingWithoutFlash = true;

      if (!didInjectMimeType) {
        (function() {
          // Is Flash installed?
          var navi = _this._navigator,
              mimeTypes = navi && navi.mimeTypes,
              type = 'application/x-shockwave-flash';
          if (mimeTypes && !mimeTypes[type]) {
            // Pretend there is one.
            mimeTypes[type] = {
              description: 'Shockwave Flash',
              enabledPlugin: {
                description: 'Shockwave Flash 16.0 r0'
              },
              suffixes: 'swf',
              type: type
            };

            didInjectMimeType = true; // flag
          }
        })();
      }

      if (!didInjectFlashDetect) {
        (function() {
          // Find FlashDetect.
          var FD = window.FlashDetect;
          if (FD && !FD.installed) {
            // Force FlashDetect to think there is one.
            Object.defineProperty(FD, 'installed', {
              configurable: true,
              set: function() {},
              get: function() { return true; }
            });
            FD.raw = 'Shockwave Flash 16.0 r0';
            FD.major = 16;
            FD.minor = 0;
            FD.revision = -1;
            FD.revisionStr = 'r0';

            didInjectFlashDetect = true; // flag
          }
        })();
      }

      if (!didInjectSoundManager) {
        (function() {
          // Find window.sm or window.soundManager.
          var SM = window.SoundManager,
              sm = window.sm || window.soundManager;
          if (SM && sm instanceof SM) {
            // Make SoundManager HTML5-Only.
            Object.defineProperty(sm, 'html5Only', {
              configurable: true,
              set: function() {},
              get: function() { return true; }
            });
            sm.reboot();

            didInjectSoundManager = true; // flag
          }
        })();
      }

      /**
       * Listen for XHR open, change audio protocol.
       * Continue only if SoundManager is ready.
       */
      if (!didInjectXHR && didInjectSoundManager) {
        (function() {
          /** @type {RegExp} */
          var rtmpRE = /(\/audio?.*protocol\s*=\s*)rtmp/gi;

          /** @type {BM~openCallback} */
          _this._openCallbacks['playWithoutFlash'] = function(openRequest, openArguments) {
            // Change protocol=rtmp to httpd if the url contains it.
            var url = openArguments[1];
            if (!rtmpRE.test(url)) {
              return; // Nothing to do.
            }
            openArguments[1] = url.replace(rtmpRE, '$1httpd');

            // Assign a onload event.
            openRequest.addEventListener('load', function() {
              // Check if this method is still available.
              var succeed = false;
              try {
                var res = JSON.parse(this.responseText);
                if (res && ['OK', 'StreamRightsUnavailable', 'SubscriptionUpgradeRequired'].indexOf(res.code) > -1) {
                  succeed = true;
                }
              } catch (e) {}

              // No, it's busted!
              if (!succeed) {
                // Revert!
                revert();
              }
            });
          };

          didInjectXHR = true; // flag
        })();
      }

      return didInjectXHR;
    };

    /**
     * @return {boolean} didInjectXHR
     */
    var revert = function() {
      // NOTE: Reverts in the reverse order.

      if (didInjectXHR) {
        (function() {
          delete _this._openCallbacks['playWithoutFlash'];

          didInjectXHR = false; // flag
        })();
      }

      if (didInjectSoundManager) {
        (function() {
          // Find window.sm or window.soundManager.
          var SM = window.SoundManager,
              sm = window.sm || window.soundManager;
          if (SM && sm instanceof SM) {
            // Revert it to false.
            Object.defineProperty(sm, 'html5Only', {
              configurable: true,
              enumerable: true,
              writable: true,
              value: false
            });
            sm.reboot();
          }

          didInjectSoundManager = false; // flag
        })();
      }

      // NOTE: Injecting mime type affects FlashDetect too.
      if (didInjectFlashDetect || didInjectMimeType) {
        (function() {
          // Find FlashDetect.
          var FD = window.FlashDetect;
          if (FD && FD.installed) {
            // Stop forcing FlashDetect.
            Object.defineProperty(FD, 'installed', {
              configurable: true,
              enumerable: true,
              writable: true,
              value: false
            });
            FD.raw = '';
            FD.major = -1;
            FD.minor = -1;
            FD.revision = -1;
            FD.revisionStr = '';
          } 

          didInjectFlashDetect = false; // flag
        })();
      }

      if (didInjectMimeType) {
        (function() {
          // Stop pretending.
          var navi = _this._navigator,
              mimeTypes = navi && navi.mimeTypes,
              type = 'application/x-shockwave-flash';
          if (mimeTypes && mimeTypes[type]) {
            delete mimeTypes[type];
          }

          didInjectMimeType = false; // Flag
        })();
      }

      _this._isPlayingWithoutFlash = false;

      // Callback.
      if (typeof callback == 'function') {
        setTimeout(callback.bind(this, _this.isFlashInstalled(false)));
      }

      return didInjectXHR;
    };

    // Prepare!
    var max = 30, curr = 0, delay = 1000; // Retry count.
    var fire = function() {
      // Start injecting. If failed,
      if (!inject()) {
        curr++;
        // Retry!
        if (curr < max) {
          setTimeout(fire, delay);
        }
        // Give up.
        else {
          revert();
        }
      }
    };

    fire();

    return true;
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
    return this._currentPlayerState().active && click(window.document.getElementById('t-love'));
  };

  /** 
   * @return {boolean}
   * @description Clicks the hate button.
   */
  BM.prototype.hate = function hate() {
    return this._currentPlayerState().active && click(window.document.getElementById('t-hate'));
  };

  /** 
   * @return {boolean}
   * @description Clicks the prev button.
   */
  BM.prototype.prev = function prev() {
    return this._currentPlayerState().active && click(window.document.getElementById('t-prev'));
  };

  /** 
   * @return {boolean}
   * @description Clicks the next button.
   */
  BM.prototype.next = function next() {
    return this._currentPlayerState().active && click(window.document.getElementById('t-next'));
  };

  /** 
   * @return {boolean}
   * @description Clicks the play/pause button.
   */
  BM.prototype.playPause = function playPause() {
    return this._currentPlayerState().active && click(window.document.getElementById('t-play'));
  };

  /** 
   * @return {boolean}
   * @description Adds the current track to My Library by explicitly calling Beats Music API.
   */
  BM.prototype.addToMyLibrary = function addToMyLibrary() {
    var _this = this;

    // Parse cookie.
    var coo = getCookies();

    // Get track ID.
    var tid = this._currentPlayerState().trackId;

    // Do the AJAX.
    if (tid && coo.user_id && coo.access_token) {
      var succeed = false, max = 15, curr = 0; // Retry count.
      
      var fire = function() {
        var prefix = coo.api_base_url || 'https://api.beatsmusic.com/api';

        _this._ajax({url: prefix}); // Pre-flight. More details at issue #10.

        var res = _this._ajax({
          type: 'PUT',
          url: prefix + '/users/' + coo.user_id + '/mymusic/' + tid,
          data: {id: tid},
          headers: {Authorization: 'Bearer ' + coo.access_token}
        });

        // Success!
        if (res && res.code == 'OK') {
          succeed = true;
        }
        // Failed, retry!
        else {
          curr++;
          if (curr < max) {
            fire();
          }
        }
      };

      fire(); // Synchronous request.

      return succeed;
    } else {
      return false;
    }
  };

  /**
   * @typedef {Object} BM~playerState
   * @property {boolean} active
   * @property {boolean} playing
   * @property {?string} trackId
   */

  /**
   * @return {BM~playerState}
   * @description Returns the current state of the player.
   */
  BM.prototype._currentPlayerState = function _currentPlayerState() {
    /** @type {BM~playerState} */
    var state = {
      active: false,
      playing: false,
      trackId: null
    };

    // If there's no .transport, the player is not initialized yet.
    if (!window.document.getElementsByClassName('transport').length) {
      return state; // false & null
    }

    // If there is .transport but also .transport--hidden, the player never played anything yet.
    if (window.document.getElementsByClassName('transport--hidden').length) {
      return state; // false & null
    }

    // It seems the player is ready.
    state.active = true;

    // Parse localStorage for info.
    try {
      var player = JSON.parse(this._localStorage.player);
      state.playing = !!(player.playing && !player.paused);
      state.trackId = player.trackId || null;
    } catch (e) {}

    return state;
  };

  /**
   * @return {boolean}
   * @description Checks if the player is playing.
   */
  BM.prototype.isPlaying = function isPlaying() {
    return this._currentPlayerState().playing;
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

  /**
   * @return {boolean}
   * @description Checks if any :focus pseudo class element exists.
   */
  BM.prototype.isOnFocus = function isOnFocus() {
    return !!window.document.querySelector(':focus');
  };

  return new BM();
})(window);

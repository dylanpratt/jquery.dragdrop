#
# Name      : jquery.dragdrop
# Author    : Steven Luscher, https://twitter.com/steveluscher
# Version   : 0.0.1-dev
# Repo      : https://github.com/steveluscher/jquery.dragdrop
# Donations : http://lakefieldmusic.com
#


jQuery ->
  #
  # requestAnimationFrame polyfill
  #

  requestAnimationPolyfillImplemented = no
  implementRequestAnimationFramePolyfill =
    # http://paulirish.com/2011/requestanimationframe-for-smart-animating/
    # http://my.opera.com/emoller/blog/2011/12/20/requestanimationframe-for-smart-er-animating
    # requestAnimationFrame polyfill by Erik Möller. fixes from Paul Irish and Tino Zijdel
    # MIT license
    ->
      if window.JQUERY_DRAGDROP_ENV_TEST
        # In test mode, this polyfill plays havoc with the specs. Disable it
        window.requestAnimationFrame = (c) -> c (new Date().getTime())
        window.cancelAnimationFrame = (id) -> # noop
        return

      lastTime = 0
      vendors = ["ms", "moz", "webkit", "o"]
      x = 0

      while x < vendors.length and not window.requestAnimationFrame
        window.requestAnimationFrame = window[vendors[x] + "RequestAnimationFrame"]
        window.cancelAnimationFrame = window[vendors[x] + "CancelAnimationFrame"] or window[vendors[x] + "CancelRequestAnimationFrame"]
        ++x
      unless window.requestAnimationFrame
        window.requestAnimationFrame = (callback, element) ->
          currTime = new Date().getTime()
          timeToCall = Math.max(0, 16 - (currTime - lastTime))
          id = window.setTimeout(->
            callback currTime + timeToCall
          , timeToCall)
          lastTime = currTime + timeToCall
          id
      unless window.cancelAnimationFrame
        window.cancelAnimationFrame = (id) ->
          clearTimeout id

      requestAnimationPolyfillImplemented = yes

  # Utility functions
  isNumber = (obj) -> (obj is +obj) or toString.call(obj) is '[object Number]'
  isNaN = (obj) -> isNumber(obj) and window.isNaN(obj)
  applyDefaults = (obj, sources...) ->
    for source in sources
      continue unless source
      for prop of source
        obj[prop] = source[prop] if obj[prop] is undefined
    obj

  $.draggable = class
    defaults:
      # Applied when the draggable is initialized
      draggableClass: 'ui-draggable'

      # Applied when a draggable is in mid-drag
      draggingClass: 'ui-draggable-dragging'

      # Helper options:
      # * original: drag the actual element
      # * clone: stick a copy of the element to the mouse
      # * (element, e) ->: stick the return value of this function to the mouse
      helper: 'original'

    # Memoize the config
    getConfig: -> @config ||= applyDefaults @options, @defaults

    constructor: (element, @options = {}) ->
      # Lazily implement a requestAnimationFrame polyfill
      implementRequestAnimationFramePolyfill() unless requestAnimationPolyfillImplemented

      # jQuery version of DOM element attached to the plugin
      @$element = $ element

      @$element
        # Attach the element event handlers
        .on
          mousedown: @handleElementMouseDown
          click: @handleElementClick

        # Mark this element as draggable with a class
        .addClass(@getConfig().draggableClass)

      # Make the plugin chainable
      this

    setupElement: ->
      # Position the draggable relative if it's currently statically positioned
      @$element.css(position: 'relative') if @config.helper is 'original' and @$element.css('position') is 'static'

      # Done!
      @setupPerformed = true

    #
    # Mouse events
    #

    handleElementMouseDown: (e) =>
      @cancelAnyScheduledDrag()

      # Bail if this is not a valid handle
      return unless @isValidHandle(e.target)

      # Store the mousedown event that started this drag
      @mousedownEvent = e

      # Start to listen for mouse events on the document
      $(document).on
        mousemove: @handleDocumentMouseMove
        mouseup: @handleDocumentMouseUp

      # Stop the mousedown event
      false

    handleElementClick: (e) =>
      # Clicks should be passed through if this interaction didn't result in a drag
      shouldPermitClick = not @dragStarted

      # Clean up
      @dragStarted = false
      @$helper = null
      @helperStartPosition = {}
      @elementStartDocumentOffset = {}
      @helperStartDocumentOffset = {}
      delete @mousedownEvent

      unless shouldPermitClick
        # Cancel the click
        e.stopImmediatePropagation()
        false

    handleDocumentMouseUp: (e) =>
      # Stop listening for mouse events on the document
      $(document).off
        mousemove: @handleMouseMove
        mouseup: @handleMouseUp

      return unless @dragStarted

      if @config.helper is 'clone'
        # Destroy the helper
        @$helper.remove()
        # Trigger the click event on the original element
        @$element.trigger('click', e)
      else
        # Remove the dragging class
        @$helper.removeClass @getConfig().draggingClass

      # Trigger the stop event
      @handleDragStop(e)

    handleDocumentMouseMove: (e) =>
      # Trigger the start event, once
      @handleDragStart(e) unless @dragStarted

      # Trigger the drag event
      @handleDrag(e)

    #
    # Draggable events
    #

    handleDragStart: (e) ->
      @cancelAnyScheduledDrag()

      # Lazily perform setup on the element
      @setupElement() unless @setupPerformed

      # Call any user-supplied start callback
      @config.start?(e)

      # Store the start offset of the draggable, with respect to the document
      @elementStartDocumentOffset = @$element.offset()

      # Configure the drag helper
      @$helper =
        switch @config.helper
          when 'clone' then @synthesizeHelperByCloning @$element
          else @$element # Use the element itself

      if @isPositionedAbsoluteish(@$helper)
        # Store the start offset of the helper, with respect to its offset parent
        @helperStartPosition = @$helper.position()
      else
        # Store the start position of the helper with respect to itself
        @helperStartPosition ||= {}
        for edge in ['top', 'left']
          @helperStartPosition[edge] = parseInt(@$helper.css edge)
          @helperStartPosition[edge] = 0 if isNaN(@helperStartPosition[edge])

      # Store the start offset of the helper, with respect to the document
      @helperStartDocumentOffset = @$helper.offset()

      @$helper
        # Apply the dragging class
        .addClass(@getConfig().draggingClass)

      # Mark the drag as having started
      @dragStarted = true

    handleDragStop: (e) ->
      @cancelAnyScheduledDrag()

      # Call any user-supplied stop callback
      @config.stop?(e)

    handleDrag: (e) ->
      @scheduleDrag =>
        # Call any user-supplied drag callback
        @getConfig().drag?(e)

        # How far has the mouse moved from its original position
        delta =
          x: e.pageX - @mousedownEvent.pageX
          y: e.pageY - @mousedownEvent.pageY

        # Move the helper
        @$helper.css
          left: parseInt(@helperStartPosition .left) + delta.x
          top: parseInt(@helperStartPosition .top) + delta.y

    #
    # Validators
    #

    isValidHandle: (element) ->
      if @config.handle
        $element = $(element)

        # Is this element the handle itself, or a descendant of the handle?
        !!$element.closest(@config.handle).length
      else
        # No handle was specified; anything is fair game
        true

    isPositionedAbsoluteish: (element) -> /fixed|absolute/.test element.css('position')

    #
    # Helpers
    #

    cancelAnyScheduledDrag: ->
      return unless @scheduledDragId

      cancelAnimationFrame(@scheduledDragId)
      @scheduledDragId = null

    scheduleDrag: (invocation) ->
      @cancelAnyScheduledDrag()
      @scheduledDragId = requestAnimationFrame =>
        invocation()
        @scheduledDragId = null

    synthesizeHelperByCloning: (element) ->
      css = {}

      # Position the helper absolutely, unless it already is-ish
      css.position = 'absolute' unless @isPositionedAbsoluteish(element)

      # Move the clone to the position of the original
      css.top = @elementStartDocumentOffset.top
      css.left = @elementStartDocumentOffset.left

      element
        # Clone the element
        .clone()
        # Remove the ID attribute from the clone
        .removeAttr('id')
        # Style the helper
        .css(css)
        # Attach it to the body
        .appendTo('body')

  $.fn.draggable = (options) ->
    this.each ->
      unless $(this).data('draggable')?
        plugin = new $.draggable(this, options)
        $(this).data('draggable', plugin)

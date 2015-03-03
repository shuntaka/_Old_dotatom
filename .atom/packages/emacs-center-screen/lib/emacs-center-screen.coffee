module.exports =
  activate: () ->
    atom.workspaceView.command "emacs-center-screen:center-screen", => @centerScreen()
  isTop: ->
    @getTop() is @getCursor() or
    @getTop() + 1 is @getCursor() or
    @getTop() + 2 is @getCursor()
  isBottom: ->
    @getBottom() is @getCursor() or
    @getBottom() - 1 is @getCursor() or
    @getBottom() - 2 is @getCursor()
  getTop: ->
    atom.workspaceView.getActiveView().getFirstVisibleScreenRow()
  getBottom: ->
    atom.workspaceView.getActiveView().getLastVisibleScreenRow()
  getCursor: ->
    atom.workspace.getActiveEditor().getCursorScreenRow()
  getHalf: ->
    parseInt (@getBottom() - @getTop()) / 2
  setScreen: (pos) ->
    if pos < (atom.workspace.getActiveEditor().getLineCount() - 1)
      atom.workspaceView.getActiveView().scrollToScreenPosition([pos, 0],  {
        center: true
      });
  pageUp: ->
    atom.workspaceView.getActiveView().pageUp()
  centerScreen: ->
    if @isTop()
      @setScreen(@getCursor() - @getHalf())
    else
      @setScreen(@getCursor() + @getHalf())

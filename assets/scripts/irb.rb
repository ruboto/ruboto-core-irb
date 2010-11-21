#######################################################
#
# irb.rb (by Scott Moyer)
# 
# This duplicates the functionality of 
# Ruboto IRB (written in Java) with a ruboto 
# script (written in Ruby).
#
#######################################################

require "ruboto.rb"
confirm_ruboto_version(6)

java_import "android.view.View"
java_import "android.view.Window"
java_import "android.view.WindowManager"
java_import "android.view.Gravity"
java_import "android.view.KeyEvent"
java_import "android.text.util.Linkify"
java_import "android.app.AlertDialog"
java_import "android.content.DialogInterface"
java_import "android.content.Context"
java_import "android.content.SharedPreferences"
java_import "android.content.res.AssetManager"
java_import "android.text.method.ScrollingMovementMethod"
java_import "android.os.Environment"
java_import "android.view.inputmethod.EditorInfo"
java_import "android.graphics.Paint"
java_import "android.graphics.Rect"


java_import "org.apache.http.client.methods.HttpGet"
java_import "org.apache.http.impl.client.BasicResponseHandler"
java_import "org.apache.http.impl.client.DefaultHttpClient"

ruboto_import_widgets :TabHost, :LinearLayout, :FrameLayout, :TabWidget, 
  :Button, :EditText, :TextView, :ListView, :ScrollView, :AutoCompleteTextView

#ruboto_import_widget :RubotoEditText, "org.ruboto"
ruboto_import_widget :LineNumberEditText, "org.ruboto.irb"

require 'stringio'
$main_binding = self.instance_eval{binding}

############################################################################################################
#
# Setup Script Dir
#

if Environment.getExternalStorageState == Environment::MEDIA_MOUNTED
  $SCRIPT_DIR = "/sdcard/jruby"
else
  $SCRIPT_DIR = $activity.getFilesDir.getAbsolutePath + "/scripts"
end
$LOAD_PATH << $SCRIPT_DIR unless $LOAD_PATH.include?($SCRIPT_DIR)

def load_asset_demos(yn_toast=false)
  Dir.mkdir($SCRIPT_DIR) unless File.directory?($SCRIPT_DIR)
  message = []
  $activity.getAssets.list('demo-scripts').map(&:to_s).each do |s|
    buf = getAssets.open("demo-scripts/#{s}", AssetManager::ACCESS_BUFFER)
    contents = []
    b = buf.read
    until b == -1 do
      contents << b.chr
      b = buf.read
    end
    message << (save(s, contents.join, false) ? "#{s} copied" : "#{s} copy failed")
  end
  toast message.join("\n") if yn_toast
end

load_asset_demos unless File.directory?($SCRIPT_DIR)


############################################################################################################
#
# Main Activity
#

$activity.start_ruboto_activity("$ruboto_irb") do
  getWindow.setSoftInputMode(
             WindowManager::LayoutParams::SOFT_INPUT_STATE_VISIBLE | 
             WindowManager::LayoutParams::SOFT_INPUT_ADJUST_RESIZE)

  prefs = getPreferences(Context::MODE_PRIVATE)
  requestWindowFeature(Window::FEATURE_NO_TITLE) if prefs.getBoolean("HideTitle", false)
  getWindow.addFlags(WindowManager::LayoutParams::FLAG_FULLSCREEN) if prefs.getBoolean("Fullscreen", false)
  prefs = nil
  
  #
  # UI setup
  #

  setup_content do
    @history = []
    prefs = getPreferences(Context::MODE_PRIVATE)
    
    # For showing line numbers in the source EditText
    @showLineNumbers = prefs.getBoolean("LineNumbers", true)
    @lineRect = Rect.new
    @paint = Paint.new
    @paint.setColor(0x880000FF)
    @paint.setTextSize(12.0)
    
    # Check to see if the url of a script came in from an http request
    script_name = "untitled.rb"
    script_code = ""
    if getIntent.getScheme == "http"
      url = getIntent.getData.toString
      script_name = url.split("/")[-1]
      begin
        script_code = DefaultHttpClient.new.execute(HttpGet.new(url), BasicResponseHandler.new)
      rescue
      end
    end

    @tabs = tab_host do
      linear_layout(:orientation => LinearLayout::VERTICAL, :height => :fill_parent) do
        @tab_widget = tab_widget(:id => AndroidIds::tabs, 
          :visibility => prefs.getBoolean("HideTabs", false) ? View::GONE : View::VISIBLE)
        frame_layout(:id => AndroidIds::tabcontent, :height => :fill_parent) do
          linear_layout(:id => 55555, :height => :fill_parent,
                        :orientation => LinearLayout::VERTICAL) do
            @irb_edit = auto_complete_text_view :id => 55560, 
                            :on_editor_action_listener => @editor_action_listener, 
                            :on_click_listener => @auto_complete_click_listener
            @irb_text = text_view :text => "#{explanation_text}\n\n>> ", :height => :fill_parent, 
                            :gravity => (Gravity::BOTTOM | Gravity::CLIP_VERTICAL), 
                            :text_color => 0xffffffff, 
                            :movement_method => ScrollingMovementMethod.new;
          end
          linear_layout(:id => 55556, :orientation => LinearLayout::VERTICAL) do
            @edit_name   = edit_text :id => 55561, :text => "untitled.rb"
            @edit_script = line_number_edit_text :id => 55562, :height => :fill_parent, 
                                       :hint => "Enter source code here.", :text => script_code,
                                       :gravity => Gravity::TOP, :horizontally_scrolling=> true
          end
          @scripts = list_view :id => 55557, :list => []
        end
      end
    end

    @defaultLeftPadding = @edit_script.getPaddingLeft
    @lineHeight = @edit_script.getLineHeight
    @edit_script.setCallbackProc(LineNumberEditText::CB_DRAW, @line_number_draw)

    registerForContextMenu(@scripts)
    load_script_list
    initHistoryAdapter

    @tabs.setup
    @tabs.addTab(@tabs.newTabSpec("irb").setContent(55555).setIndicator("IRB"))
    @tabs.addTab(@tabs.newTabSpec("editor").setContent(55556).setIndicator("Editor"))
    @tabs.addTab(@tabs.newTabSpec("scripts").setContent(55557).setIndicator("Scripts"))
    @tabs.setOnTabChangedListener(@tab_change_listener)
    @tabs.setCurrentTabByTag("editor") unless script_code == ""
    @tabs
  end

  #
  # Script list item click
  #

  handle_item_click do |adapter_view, view, pos, item_id|
    edit @scripts_list[pos]
  end

  #
  # Menu Items
  #

  handle_create_options_menu do |menu|
    add_menu("Save", R::drawable::ic_menu_save) do 
      save(@edit_name.getText.toString, @edit_script.getText.toString)
    end

    add_menu("Execute", Ruboto::R::drawable::ic_menu_play) do
      execute @edit_script.getText.toString,
               "[Running editor script (#{@edit_name.getText})]"
      @tabs.setCurrentTabByTag("irb")
    end

    add_menu("New", R::drawable::ic_menu_add) do 
      @edit_name.setText "untitled.rb"
      @edit_script.setText ""
      @tabs.setCurrentTabByTag("editor")
    end

    add_menu("Edit history", R::drawable::ic_menu_recent_history) do
      edit "untitled.rb", @history.join("\n")
    end

    add_menu("About", R::drawable::ic_menu_info_details) do
      AlertDialog::Builder.new(self).
        setTitle("About Ruboto IRB v0.3.2").
        setView(scroll_view do
                  tv = text_view :padding => [5,5,5,5], :text => about_text
                  Linkify.addLinks(tv, Linkify::ALL)
                end).
        setPositiveButton("Ok", @dialog_click_listener).
        create.
        show
    end

    add_menu("Reload scripts list") do 
      @tabs.setCurrentTabByTag("scripts")
      load_script_list
    end

    add_menu("Reload demos from assets") do 
      load_asset_demos(true)
    end

    add_menu("Clear IRB output") do 
      @irb_text.setText(">> ")
      @tabs.setCurrentTabByTag("irb")
    end

    add_menu("Edit IRB output") do 
      edit "untitled.rb", @irb_text.getText.toString
    end

    add_menu("Toggle screen real estate") do 
      prefs = getPreferences(Context::MODE_PRIVATE)
      prefsEditor = prefs.edit

      @tab_widget.setVisibility(@tab_widget.getVisibility == View::VISIBLE ? View::GONE : View::VISIBLE)
      if prefs.getBoolean("Fullscreen", false)
        getWindow.clearFlags(WindowManager::LayoutParams::FLAG_FULLSCREEN)
      else
        getWindow.addFlags(WindowManager::LayoutParams::FLAG_FULLSCREEN)
      end

      prefsEditor.putBoolean("HideTabs", @tab_widget.getVisibility() == View::GONE)
      prefsEditor.putBoolean("Fullscreen", !prefs.getBoolean("Fullscreen", false))
      prefsEditor.putBoolean("HideTitle", !prefs.getBoolean("HideTitle", false))
      prefsEditor.commit
    end

    add_menu("Toggle line numbers") do 
      @showLineNumbers = !@showLineNumbers
      @tabs.setCurrentTabByTag("editor")

      prefs = getPreferences(Context::MODE_PRIVATE)
      prefsEditor = prefs.edit
      prefsEditor.putBoolean("LineNumbers", @showLineNumbers)
      prefsEditor.commit
    end
    
    add_menu("Go to line number") do 
      @tabs.setCurrentTabByTag("editor")
      @goto_edit_text = edit_text
      @goto_dialog = AlertDialog::Builder.new(self).
        setTitle("Go to line").
        setView(@goto_edit_text).
        setPositiveButton("Go", @dialog_click_listener).
        setNegativeButton("Cancel", @dialog_click_listener).
        create
      @goto_dialog.show
    end
    
    add_menu("Reload irb script") do 
      url = "http://ruboto.scottmoyer.org/scripts/irb.rb"
      contents = DefaultHttpClient.new.execute(HttpGet.new(url), BasicResponseHandler.new)
      File.open("irb.rb","w") {|f| f.write contents}
      toast "Updated irb.rb!"
      finish
    end
    
    true
  end

  #
  # Script list context menu items
  #

  handle_create_context_menu do |menu, view, menu_info|
    add_context_menu("Edit") {|pos| edit @scripts_list[pos]}

    add_context_menu("Execute") do |pos| 
      begin
        execute IO.read("#{$SCRIPT_DIR}/#{@scripts_list[pos]}"), "[Running #{@scripts_list[pos]}]"
      rescue
        toast "#{@scripts_list[pos]} not found!"
      end
    end

    add_context_menu("Delete") do |pos| 
      @confirm_delete = @scripts_list[pos]
      @delete_dialog = AlertDialog::Builder.new(self).
              setMessage("Delete #{@confirm_delete}?").
              setCancelable(false).
              setPositiveButton("Yes", @dialog_click_listener).
              setNegativeButton("No", @dialog_click_listener).
              create
      @delete_dialog.show
    end

    true
  end

  #
  # Delete confirmation dialog buttons
  #

  ruboto_import "org.ruboto.irb.MyDialogClickListener"
  @dialog_click_listener = MyDialogClickListener.new.handle_click do |dialog, which|
    if dialog == @delete_dialog and @confirm_delete and which == DialogInterface::BUTTON_POSITIVE
      begin 
        File.delete "#{$SCRIPT_DIR}/#{@confirm_delete}"
        toast "#{@confirm_delete} deleted"
        load_script_list
      rescue
        toast "Deleted failed!"
      end
      @confirm_delete = nil
    elsif dialog == @goto_dialog and which == DialogInterface::BUTTON_POSITIVE
      begin 
		i = @goto_edit_text.getText.toString.to_i
		@edit_script.scrollTo(0, (i-1) * @edit_script.getLineHeight);
      rescue
      end
    end
  end

  #
  # Tab change
  #

  ruboto_import "org.ruboto.irb.MyTabChangeListener"
  @tab_change_listener = MyTabChangeListener.new.handle_tab_changed do |tab|
    if tab == "scripts"
        getSystemService(Context::INPUT_METHOD_SERVICE).
           hideSoftInputFromWindow(@tabs.getWindowToken, 0)
    end
  end

  #
  # On Click for IRB EditText - force it to pop up
  #
  
  @auto_complete_click_listener = RubotoOnClickListener.new.handle_click do |view|
    @irb_edit.showDropDown unless @history.empty?
  end

  #
  # Editor actions for keeping the history of the IRB EditText
  #
  ruboto_import "org.ruboto.irb.MyEditorActionListener"
  @editor_action_listener = MyEditorActionListener.new.handle_editor_action do |view, action_id, event|
    return false unless action_id == EditorInfo::IME_NULL
    line = @irb_edit.getText.toString
    return true if line == ""

    i = @history.index(line)
    if i
      @history[i..i] = nil
      @adapter.remove(@adapter.getItem(i))
    end

    @history.unshift line
    @adapter.insert(line, 0)
    execute line
    @irb_edit.setText ""

    return true
  end

  #
  # Line number EditText
  #

  @line_number_draw = Proc.new do |view, canvas|
#  handle_draw do |view, canvas|
    lineCount = view.getLineCount
    leftPadding = @defaultLeftPadding + ((!@showLineNumbers || lineCount == 0) ? 0 :
                                         ((Math.log10(lineCount).to_i + 1) * 10))
    view.setPadding(leftPadding, view.getPaddingTop, view.getPaddingRight, view.getPaddingBottom)

    if (@showLineNumbers)
        scrollX = view.getScrollX
        scrollY = view.getScrollY
        topLineNumber = max(1, ((scrollY - view.getPaddingTop) / @lineHeight))
        bottomLineNumber = min(view.getLineCount, topLineNumber + 1 + (view.getHeight / @lineHeight).to_i)
        
    	canvas.save

        canvas.clipRect(0, 
						view.getPaddingTop + scrollY, 
						view.getPaddingLeft + scrollX,
						view.getBottom - view.getTop - view.getPaddingBottom + scrollY)
						
      	view.getLineBounds(topLineNumber - 1, @lineRect)
      	baseline =  @lineRect.bottom - 8
        topLineNumber.upto(bottomLineNumber) do |i|
            canvas.drawText(i.to_s, @defaultLeftPadding + scrollX, baseline, @paint)
            baseline += @lineHeight
        end

        canvas.restore
    end
  end
  
  #
  # Save and restore state of history text
  #

  handle_save_instance_state do |savedInstanceState|
    savedInstanceState.putString(  "history",     @history.join("\n")) if @history
    savedInstanceState.putInt(     "tab",         @tabs.getCurrentTab) if @tabs
  end

  handle_restore_instance_state do |savedInstanceState|
    @history = savedInstanceState.containsKey("history") ? savedInstanceState.getString("history").split("\n") : []
    @tabs.setCurrentTab(savedInstanceState.getInt("tab")) if savedInstanceState.containsKey("tab")
    initHistoryAdapter
  end

  #
  # Support methods
  #

  def self.min(a, b)
    a > b ? b : a
  end
  
  def self.max(a, b)
    a > b ? a : b
  end

  def self.initHistoryAdapter
    @adapter = ArrayAdapter.new(self, R::layout::simple_dropdown_item_1line, @history.to_java(:string))
    @irb_edit.setAdapter(@adapter)
  end

  def self.load_script_list
    @scripts_list = Dir.glob("#{$SCRIPT_DIR}/*.rb").map{|i| i.split('/')[-1]} .sort
    @scripts.reload_list(@scripts_list)
  end

  def self.edit name, code=nil
    @edit_name.setText name
    @edit_script.setText code ? code : IO.read("#{$SCRIPT_DIR}/#{name}").gsub("\r", "")
    @tabs.setCurrentTabByTag("editor")
  end

  def self.execute source, display=nil
    @tabs.setCurrentTabByTag("irb")

    old_out, $stdout = $stdout, StringIO.new
    begin
      @irb_text.append(display || source)
      rv = $main_binding.eval(source)
      $stdout, new_out = old_out, $stdout 
      @irb_text.append "\n#{new_out.string}=> #{rv.inspect}\n>> "
    rescue => e
      $stdout = old_out
      @irb_text.append "\n#{e.to_s}\n#{e.backtrace.join("\n")}\n>> "
    end
  end

  def self.save name, source, yn_toast=true
    begin
      File.open("#{$SCRIPT_DIR}/#{name}", 'w') {|file| file.write(source)}
      @tabs.setCurrentTabByTag("scripts")
      toast "Saved #{name}" if yn_toast
      load_script_list
      true
    rescue
      toast "Save failed!" if yn_toast
      false
    end
  end

  def self.explanation_text
"This script duplicates the functionality of Ruboto IRB (written in Java) with a ruboto-core application (written in Ruby). There are several differences:

1) A few scripts have been removed. demo-ruboto-irb.rb and ruboto.rb are now parts of this app, so they are not with the demo scripts.

2) There is a bug that you can trigger by doing a \"require 'date'\" (or some other date/time calls). It causes a StackOverflow exception and sometimes Force CLoses the app. This seems to be related to known issues with the stack depth with respect to various dynamic languages. We're working on a solution."
  end

  def self.about_text
"Ruboto IRB is a UI for scripting Android using the Ruby language through JRuby.

Source code:
http://github.com/ruboto/ruboto-irb
http://github.com/ruboto/ruboto-core

Join us or give feedback:
http://groups.google.com/group/ruboto

Developers:
Charlie Nutter
Jan Berkel
Scott Moyer
Daniel Jackoway

JRuby Project:
http://jruby.org

Icon:
Ruby Visual Identity Team
http://rubyidentity.org
CC ShareAlike 2.5"
  end
end

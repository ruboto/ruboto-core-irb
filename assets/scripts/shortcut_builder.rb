#######################################################
#
# shortcut_builder.rb (by Scott Moyer)
# 
# Displays a list of script and returns a shortcut intent
# when one is selected.
#
#######################################################

require "ruboto.rb"
confirm_ruboto_version(4)

java_import "android.content.Intent"
ruboto_import_widget :ListView; :TextView

$SCRIPT_DIR = "/sdcard/jruby"

$activity.start_ruboto_activity("$shortcut_builder") do
  setTitle("Select a Ruboto Script")

  setup_content do
    @scripts = Dir.glob("#{$SCRIPT_DIR}/*.rb").map{|i| i.split('/')[-1]} .sort
    list_view :list => @scripts #, :empty_view => text_view(:text => "No scripts loaded yet.")
  end
  
  handle_item_click do |av, v, pos, an_id|
    sc_intent = Intent.new
    sc_intent.setAction("org.ruboto.intent.action.LAUNCH_SCRIPT")
    sc_intent.addCategory("android.intent.category.DEFAULT")
    sc_intent.putExtra("org.ruboto.extra.SCRIPT_NAME", @scripts[pos])

    intent = Intent.new
    intent.putExtra(Intent::EXTRA_SHORTCUT_INTENT, sc_intent)
    intent.putExtra(Intent::EXTRA_SHORTCUT_NAME, @scripts[pos])
    intent.putExtra(Intent::EXTRA_SHORTCUT_ICON_RESOURCE, 
                      Intent::ShortcutIconResource.fromContext(self, Ruboto::R::drawable::icon))

    setResult(intent ? Activity::RESULT_OK : Activity::RESULT_CANCELED, intent)
    finish();
  end
end

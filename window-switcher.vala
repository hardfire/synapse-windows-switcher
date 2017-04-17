namespace Synapse
{
  public class WindowSwitcherPlugin: Object, Activatable, ActionProvider, ItemProvider
  {
    // a mandatory property
    public bool enabled { get; set; default = true; }

    // this method is called when a plugin is enabled
    // use it to initialize your plugin
    public void activate ()
    {
    }

    // this method is called when a plugin is disabled
    // use it to free the resources you're using
    public void deactivate ()
    {
    }

    // register your plugin in the UI
    static void register_plugin ()
    {
      PluginRegistry.get_default ().register_plugin (
        typeof (WindowSwitcherPlugin),
        _("Window Switcher"), // plugin title
        _("Plugin to Switch Windows"), // description
        "system-run", // icon name
        register_plugin, // reference to this function
        Environment.find_program_in_path ("wmctrl") != null, // true if user's system has all required components which the plugin needs
        _("wmctrl is not installed") // error message
        );
    }

    static construct
    {
      // register the plugin when the class is constructed
      register_plugin ();
    }

    //private WindowMatch action;
    //construct
    //{
      //action = new WindowMatch();
    //}

    // an optional method to improve the speed of searches,
    // if you return false here, the search method won't be called
    // for this query
    public bool handles_query (Query query)
    {
      // we will only search in the "Actions" category (that includes "All" as well)
      return (QueryFlags.ACTIONS in query.query_type);
    }


    public async ResultSet? search (Query q) throws SearchError
    {
      var our_results = QueryFlags.ACTIONS;
      var common_flags = q.query_type & our_results;
      // ignore short searches
      if (common_flags == 0 || q.query_string.length <= 1) return null;

      // strip query
      q.query_string = q.query_string.strip ();

      q.check_cancellable ();

      string[] argv = {"wmctrl", "-l", "-x"};

      try
      {
        Pid pid;
        int read_fd;

        // FIXME: fork on every letter... yey!
        Process.spawn_async_with_pipes (null, argv, null,
                                        SpawnFlags.SEARCH_PATH,
                                        null, out pid, null, out read_fd);

        UnixInputStream read_stream = new UnixInputStream (read_fd, true);
        DataInputStream locate_output = new DataInputStream (read_stream);
        string? line = null;

        // make sure this method is called before returning any results
        var results = new ResultSet ();

        Regex filter = new Regex ("(\\S+)\\s*\\S*\\s*(\\S*)\\s*\\S*\\s*(.*)",
                                  RegexCompileFlags.CASELESS);

        var matchers = Query.get_matchers_for_query (q.query_string, 0,
                                                     RegexCompileFlags.OPTIMIZE | RegexCompileFlags.CASELESS);

        do
        {
          line = yield locate_output.read_line_async (Priority.DEFAULT_IDLE, q.cancellable);
          if (line != null)
          {
            MatchInfo matchInfo;
            if (filter.match (line, 0, out matchInfo))
            {
              string id = matchInfo.fetch(1);
              string name = matchInfo.fetch(2);
              string title = matchInfo.fetch(3);

              foreach (var matcher in matchers)
              {
                if (matcher.key.match (title))
                {
                  debug("Window Manager %s - AVERAGE \n", title);
                  results.add (new WindowMatch(id, title), MatchScore.HIGHEST);
                  break;
                }
                if (matcher.key.match (name))
                {
                  debug("Window Manger %s - HIGHEST\n", name);
                  results.add (new WindowMatch(id, name), MatchScore.HIGHEST);
                  break;
                }
              }
            }
            q.check_cancellable ();
          }
        } while (line != null);

        q.check_cancellable ();
        return results;
      }
      catch (Error err)
      {
        if (!q.is_cancelled ()) warning ("%s", err.message);
      }

      // make sure this method is called before returning any results
      q.check_cancellable ();
      return null;
    }

    // define our Match object
    private class WindowMatch : Match
    {
      // Our own
      public string windowId{ get; construct set; }

      public override void execute (Match match)
      {
        WindowMatch? wm = match as WindowMatch;
        if ( match == null ) return;
        string[] argv = {"wmctrl", "-i", "-a", wm.windowId};
        Process.spawn_async_with_pipes (null, argv, null,
                                        SpawnFlags.SEARCH_PATH,
                                        null, null, null, null);
      }

      public WindowMatch (string windowId, string title)
      {
        Object (title: title,
                description: "window '" + title + "'",
                has_thumbnail: false, icon_name: "system-run",
                windowId: windowId);
      }
    }

    public ResultSet? find_for_match (ref Query query, Match match)
    {
      var results = new ResultSet ();
      if (match is WindowMatch)
      {
        WindowMatch? wm = match as WindowMatch;
        results.add(match, MatchScore.AVERAGE);
      }
      return results;
    }

  }
}

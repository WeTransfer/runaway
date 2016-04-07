# runaway

Spin off work into child processes and terminate it on time. If you need the process to be done
within a certain time period (and if it takes longer it probably is hanging):

    Runaway.spin(must_quite_within: 15) do # ensures termination within 15 seconds
      `/bin/proprietary_render_server/bin/render --put-server-on-fire=yes`
    end

If the child process quits with the exit code of 0 it is considered a "clean" termination.
Anything else (any non-zero exit status) is considered a failure in the child process and
will cause an exception to be raised in the master.

The `spin` method in the master blocks until the child process terminates.

## Contributing to runaway
 
* Check out the latest master to make sure the feature hasn't been implemented or the bug hasn't been fixed yet.
* Check out the issue tracker to make sure someone already hasn't requested it and/or contributed it.
* Fork the project.
* Start a feature/bugfix branch.
* Commit and push until you are happy with your contribution.
* Make sure to add tests for it. This is important so I don't break it in a future version unintentionally.
* Please try not to mess with the Rakefile, version, or history. If you want to have your own version, or is otherwise necessary, that is fine, but please isolate to its own commit so I can cherry-pick around it.

## Copyright

Copyright (c) 2016 Julik Tarkhanov. See LICENSE.txt for
further details.


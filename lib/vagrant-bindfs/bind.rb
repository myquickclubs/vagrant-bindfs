module VagrantPlugins
  module Bindfs
    module Action
      class Bind
        def initialize(app, env)
          @app = app
          @env = env
        end

        def call(env)
          @app.call(env)
          @env = env

          @machine = env[:machine]

          unless binded_folders.empty?
            handle_bindfs_installation
            bind_folders
          end
        end

        def binded_folders
          @machine.config.bindfs.bind_folders
        end

        def default_options
          current_defaults = @machine.config.bindfs.default_options

          new_defaults = {}.tap do |new_default|
            current_defaults.each do |key, value|
              new_default[key.to_s.gsub("_", "-")] = value
            end
          end

          available_options.merge(
            available_shortcuts
          ).merge(
            available_flags
          ).merge(
            new_defaults
          )
        end

        def normalize_options(current_options)
          new_options = {}.tap do |new_option|
            current_options.each do |key, value|
              new_option[key.to_s.gsub("_", "-")] = value
            end
          end

          source = new_options.delete("source-path")
          dest = new_options.delete("dest-path")
          options = default_options.merge(new_options)

          args = [].tap do |arg|
            options.each do |key, value|
              next if key == "force-user" and options.keys.include? "owner"
              next if key == "force-user" and options.keys.include? "u"

              next if key == "force-group" and options.keys.include? "group"
              next if key == "force-group" and options.keys.include? "g"

              next if key == "mirror" and options.keys.include? "m"
              next if key == "mirror-only" and options.keys.include? "M"
              next if key == "perms" and options.keys.include? "p"

              if available_flags.keys.include? key
                arg.push "--#{key}" if value
                next
              end

              next if value.nil?

              if available_shortcuts.keys.include?(key) or additional_shortcuts.keys.include?(key)
                arg.push "-#{key} '#{value}'"
                next
              end

              if available_options.keys.include?(key) or additional_options.keys.include?(key)
                arg.push "--#{key}='#{value}'"
                next
              end
            end
          end

          [
            source,
            dest,
            args.join(" ")
          ]
        end

        def bind_folders
          @env[:ui].info I18n.t("vagrant.config.bindfs.status.binding_all")

          binded_folders.each do |id, options|
            source, dest, args = normalize_options(options)

            bind_command = [
              "bindfs",
              args,
              source,
              dest
            ].compact

            unless @machine.communicate.test("test -d #{source}")
              @env[:ui].error I18n.t(
                "vagrant.config.bindfs.errors.source_path_not_exist",
                path: source
              )

              next
            end

            if @machine.communicate.test("mount | grep bindfs | grep #{dest}")
              @env[:ui].info I18n.t(
                "vagrant.config.bindfs.already_mounted",
                dest: dest
              )

              next
            end

            @env[:ui].info I18n.t(
              "vagrant.config.bindfs.status.binding_entry",
              dest: dest,
              source: source
            )

            @machine.communicate.tap do |comm|
              comm.sudo("mkdir -p #{dest}")

              comm.sudo(
                bind_command.join(" "),
                error_class: Error,
                error_key: :binding_failed
              )
            end
          end
        end

        def handle_bindfs_installation
          unless @machine.guest.capability(:bindfs_installed)
            @env[:ui].warn(I18n.t("vagrant.config.bindfs.not_installed"))

            unless @machine.guest.capability(:bindfs_install)
              raise Vagrant::Bindfs::Error, :cannot_install
            end
          end
        end

        def available_options
          @available_options ||= {
            "force-user" => "vagrant",
            "force-group" => "vagrant",
            "perms" => "u=rwX:g=rD:o=rD",
            "mirror" => nil,
            "mirror-only" => nil,
            "map" => nil,
            "create-for-user" => nil,
            "create-for-group" => nil,
            "create-with-perms" => nil,
            "chmod-filter" => nil,
            "read-rate" => nil,
            "write-rate" => nil
          }.freeze
        end

        def additional_options
          @additional_options ||= {
            # only for old versions, this will result in an error
            # if you try that within current bindfs versions!
            "owner" => "vagrant",
            "group" => "vagrant"
          }.freeze
        end

        def available_shortcuts
          @available_shortcuts ||= {
            "o" => nil
          }.freeze
        end

        def additional_shortcuts
          @additional_shortcuts ||= {
            "u" => nil, # overwrites the value of force-user
            "g" => nil, # overwrites the value of force-group
            "m" => nil, # overwrites the value of mirror
            "M" => nil, # overwrites the value of mirror-only
            "p" => nil  # overwrites the value of perms
          }.freeze
        end

        def available_flags
          @available_flags ||= {
            "create-as-user" => false,
            "create-as-mounter" => false,
            "chown-normal" => false,
            "chown-ignore" => false,
            "chown-deny" => false,
            "chgrp-normal" => false,
            "chgrp-ignore" => false,
            "chgrp-deny" => false,
            "chmod-normal" => false,
            "chmod-ignore" => false,
            "chmod-deny" => false,
            "chmod-allow-x" => false,
            "xattr-none" => false,
            "xattr-ro" => false,
            "xattr-rw" => false,
            "no-allow-other" => false,
            "realistic-permissions" => false,
            "ctime-from-mtime" => false,
            "hide-hard-links" => false,
            "multithreaded" => false
          }.freeze
        end
      end
    end
  end
end

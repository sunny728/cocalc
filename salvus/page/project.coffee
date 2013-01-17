###############################################################################
#
# Project page -- browse the files in a project, etc.
#
###############################################################################

{top_navbar}    = require('top_navbar')
{salvus_client} = require('salvus_client')
{alert_message} = require('alerts')
{series}        = require('async')
{defaults, required, to_json, from_json, trunc, keys} = require('misc')

MAX_TITLE_LENGTH = 25

templates = $("#salvus-project-templates")
template_project_file          = templates.find(".project-file-link")
template_project_directory     = templates.find(".project-directory-link")
template_home_icon             = templates.find(".project-home-icon")
template_new_file_icon         = templates.find(".project-new-file-icon")
template_segment_sep           = templates.find(".project-segment-sep")
template_new_file_link         = templates.find(".project-new-file-link")
template_project_commits       = templates.find(".project-commits")
template_project_commit_single = templates.find(".project-commit-single")
template_project_branch_single = templates.find(".project-branch-single")

class ProjectPage
    constructor: (@project) ->
        @container = templates.find(".salvus-project").clone()
        $("#footer").before(@container)

        @container.top_navbar
            id    : @project.project_id
            label : @project.project_id

        @init_tabs()
        @update_topbar()

        @current_path = []
        @reload()

        # Make it so editing the title and description of the project
        # sends a message to the hub.
        that = @
        @container.find(".project-project_title").blur () ->
            new_title = $(@).text()
            if new_title != that.project.title
                salvus_client.update_project_data
                    project_id : that.project.project_id
                    data       : {title:new_title}
                    cb         : (err, mesg) ->
                        if err
                            alert_message(type:'error', message:"Error contacting server to save modified project title.")
                        else if mesg.event == "error"
                            alert_message(type:'error', message:mesg.error)
                        else
                            that.project.title = new_title

        @container.find(".project-project_description").blur () ->
            new_desc = $(@).text()
            if new_desc != that.project.description
                salvus_client.update_project_data
                    project_id : that.project.project_id
                    data       : {description:new_desc}
                    cb         : (err, mesg) ->
                        if err
                            alert_message(type:'error', message:err)
                        else if mesg.event == "error"
                            alert_message(type:'error', message:mesg.error)
                        else
                            that.project.description = new_desc


        # Make it so typing something into the "create a new branch..." box
        # makes a new branch.
        @container.find(".project-branches").find('form').submit () ->
            that.branch_op($(@).find("input").val(), 'create')
            return false

        file_tools = @container.find(".project-file-tools")
        file_tools.find("a[href=#delete]").click () -> that.delete_current_path()
        file_tools.find("a[href=#rename]").click () -> that.rename_current_path()
        file_tools.find("a[href=#move]").click () -> that.move_current_path()

        ########################################
        # Only for temporary testing
        #########################################

        @container.find(".project-new-file").click(@new_file_dialog)
        @container.find(".project-save").click(() => @save_project())
        @container.find(".project-close").click(@close_project_dialog)

        @container.find(".project-meta").click @reload

        @container.find(".project-read-text-file").click () =>
            salvus_client.read_text_file_from_project
                project_id : @project.project_id
                path : 'new_file.txt'
                cb : (err, contents) ->
                    console.log("err = #{err}")
                    console.log("contents =", contents)

        @container.find(".project-read-file").click () =>
            salvus_client.read_file_from_project
                project_id : @project.project_id
                path : 'new_file.txt'
                cb : (err, url) ->
                    console.log("err = #{err}")
                    console.log("url =", url)
                    # test it manually at this point..

        @container.find(".project-move-file").click () =>
            salvus_client.move_file_in_project
                project_id : @project.project_id
                src : 'new_file.txt'
                dest : 'new_file2.txt'
                cb : (err, mesg) ->
                    console.log("err = #{err}, mesg = ", mesg)

        @container.find(".project-make-directory").click () =>
            salvus_client.make_directory_in_project
                project_id : @project.project_id
                path : 'new_directory'
                cb : (err, mesg) ->
                    console.log("err = #{err}, mesg = ", mesg)

        @container.find(".project-remove-file").click () =>
            salvus_client.remove_file_from_project
                project_id : @project.project_id
                path : 'new_file.txt'
                cb : (err, mesg) ->
                    console.log("err = #{err}, mesg = ", mesg)

        @container.find(".project-remove-directory").click () =>
            salvus_client.remove_file_from_project
                project_id : @project.project_id
                path : 'new_directory'
                cb : (err, mesg) ->
                    console.log("err = #{err}, mesg = ", mesg)

    branch_op: (branch, op) =>
        # op must be one of ['create', 'checkout', 'delete', 'merge']

        # Quick client-side check for obviously invalid branch name
        if branch.length == 0 or branch.split(/\s+/g).length != 1
            alert_message(type:'error', message:"Invalid branch name '#{branch}'")
            return

        series([
            (c) =>
                salvus_client.project_branch_op
                    project_id : @project.project_id
                    op         : op
                    branch     : branch
                    cb         : (err, mesg) ->
                        if err
                            alert_message(type:'error', message:err)
                            c(true) # fail
                        else if mesg.event == "error"
                            alert_message(type:'error', message:mesg.error)
                            c(true) # fail
                        else
                            alert_message(message:"#{op} branch '#{branch}'")
                            c()  # success
            (c) =>
                @save_project(c)
            (c) =>
                @reload()
        ])

    init_tabs: () ->
        @tabs = []
        that = @
        for item in @container.find(".nav-tabs").children()
            t = $(item)
            name = t.find("a").attr('href').slice(1)
            t.data("name", name)
            @tabs.push(label:t, name:name, target:@container.find(".#{name}"))
            t.click () ->
                that.display_tab($(@).data("name"))
                return false

        # @display_tab("project-branches") # TODO -- for testing.

    display_tab: (name) =>
        for tab in @tabs
            if tab.name == name
                tab.target.show()
                tab.label.addClass('active')
            else
                tab.target.hide()
                tab.label.removeClass('active')

    save_project: (cb) =>
        salvus_client.save_project
            project_id : @project.project_id
            commit_mesg : "a commit message"
            cb         : (err, mesg) ->
                if err
                    alert_message(type:"error", message:"Connection error.")
                else if mesg.event == "error"
                    alert_message(type:"error", message:mesg.error)
                else
                    alert_message(type:"success", message: "Project successfully saved.")
                if cb?
                    cb()

    close_project_dialog: () =>
        salvus_client.close_project
            project_id : @project.project_id
            cb         : (err, mesg) ->
                if err
                    alert_message(type:"error", message:"Connection error.")
                else if mesg.event == "error"
                    alert_message(type:"error", message:mesg.error)
                else
                    alert_message(type:"success", message: "Project closed.")

    new_file_dialog: () =>
        salvus_client.write_text_file_to_project
            project_id : @project.project_id,
            path       : 'new_file.txt',
            content    : 'This is a new file.'
            cb         : (err, mesg) ->
                if err
                    alert_message(type:"error", message:"Connection error.")
                else if mesg.event == "error"
                    alert_message(type:"error", message:mesg.error)
                else
                    alert_message(type:"success", message: "New file created.")

    new_file: (path) =>
        salvus_client.write_text_file_to_project
            project_id : @project.project_id
            path       : "#{path}/untitled"
            content    : ""
            cb : (err, mesg) =>
                if err
                    alert_message(type:"error", message:"Connection error.")
                else if mesg.event == "error"
                    alert_message(type:"error", message:mesg.error)
                else
                    alert_message(type:"success", message: "New file created.")
                    salvus_client.save_project
                        project_id : @project.project_id
                        commit_mesg : "Created a new file."
                        cb : (err, mesg) =>
                            if not err and mesg.event != 'error'
                                @reload()

    load_from_server: (opts) ->
        opts = defaults opts,
            project_id : required
            cb         : undefined

        salvus_client.get_project
            cb : (error, project) =>
                if error
                    opts.cb?(error)
                else
                    @project = project
                    @update_view()
                    opts.cb?()

    save_to_server: (opts) ->
        opts = defaults opts,
            timeout : 10

        salvus_client.update_project_data
            data    : @project
            cb      : opts.cb
            timeout : opts.timeout

    update_topbar: () ->
        if not @project?
            return

        @container.find(".project-project_title").text(@project.title)
        @container.find(".project-project_description").text(@project.description)

        label = @project.title.slice(0,MAX_TITLE_LENGTH) + if @project.title.length > MAX_TITLE_LENGTH then "..." else ""
        top_navbar.set_button_label(@project.project_id, label)
        return @


    reload: () =>
        salvus_client.get_project_meta
            project_id : @project.project_id
            cb  : (err, _meta) =>
                if err
                    alert_message(type:'error', message:err)
                else
                    files = from_json(_meta.files)
                    logs = from_json(_meta.logs)
                    branches = keys(files)
                    branches.sort()
                    @meta =
                        files          : files
                        logs           : logs
                        current_branch : _meta.current_branch
                        display_branch : _meta.current_branch  # start the same
                        branches       : branches
                    @update_file_list_tab()
                    @update_commits_tab()
                    @update_branches_tab()

    # Returns array of objects
    #    {filename:..., is_file:..., commit:...reference to commit object if is_file true...}
    # for the current working directory and branch.
    # If the current_path is invalid, return the empty array.
    #
    # If the current_path is a file, returns the commit id of the last change to the file.
    current_files: () =>
        file_data = @meta.files[@meta.display_branch]
        commits = @meta.logs[@meta.display_branch].commits
        for segment in @current_path
            file_data = file_data[segment]
            if not file_data?
                return []

        # It's a file instead of a directory.
        if typeof file_data == "string"
            return file_data # the commit id

        directories = []
        files = []
        for filename, d of file_data
            # TODO -- make it possible to show hidden files via a checkbox
            if filename[0] == '.'
                continue
            obj = {filename:filename}
            if typeof d == 'string'  # a commit id -- consult the commit log
                obj.is_file = true
                obj.commit = commits[d]
                files.push(obj)
            else  # a directory
                obj.is_file = false
                directories.push(obj)

        cmp = (a,b) ->
            if a.filename < b.filename
                return -1
            else if a.filename == b.filename
                return 0
            else
                return 1
        directories.sort(cmp)
        files.sort(cmp)
        return directories.concat(files)

    # Render the slash-separated and clickable path that sits above
    # the list of files (or current file)
    update_current_path: () =>
        t = @container.find(".project-file-listing-current_path")
        t.empty()
        t.append($("<a>").html(template_home_icon.clone().click(() =>
            @current_path=[]; @update_file_list_tab())))

        file_data = @meta.files[@meta.display_branch]
        new_current_path = []
        that = @
        for segment in @current_path
            file_data = file_data[segment]
            new_current_path.push(segment)
            t.append(template_segment_sep.clone())
            t.append($("<a>"
            ).text(segment
            ).data("current_path",new_current_path[..]  # make a copy
            ).click((elt) =>
                @current_path = $(elt.target).data("current_path")
                @update_file_list_tab()
            ))

        if typeof file_data != "string"
            # It's a directory, so put a link to create a new file or directory in it.
            t.append(template_segment_sep.clone())
            t.append(template_new_file_link.clone().data("current_path", @current_path).click( (elt) ->
                that.new_file($(@).data("current_path").join('/'))
            ))  #.tooltip(placement:'right'))  # TODO -- should use special plugin and depend on settings.

    render_file_display: (path, cb) =>
        salvus_client.read_text_file_from_project
            project_id : @project.project_id
            timeout : 3
            path : path
            cb : (err, mesg) ->
                if err
                    cb($("<div>").html("Unable to load file..."))
                else if mesg.event == 'error'
                    cb($("<div>").html(mesg.error))
                else
                    cb($("<pre>").text(mesg.content))

    # Update the listing of files in the current_path, or display of the current file.
    update_file_list_tab: () =>
        # Update the display of the path above the listing or file preview
        @update_current_path()

        # Now rendering the listing or file preview
        file_or_listing = @container.find(".project-file-listing-file-list")
        file_or_listing.empty()

        current = @current_files()
        that = @

        if typeof current == "string"
            # A file instead of a directory listing.

            # The path to the file.
            path = @current_path.join('/')

            # Show a spinner if the file takes more than some amount of
            # time to load from the server.
            spinner = @container.find(".project-file-listing-spinner")
            t = setTimeout((()->spinner.show().spin()), 500)
            @render_file_display path, (x) ->
                clearTimeout(t)  # make sure not to show the spinner anyways.
                spinner.spin(false).hide()
                file_or_listing.append(x)
        else
            # A directory listing (as an array)
            for obj in current
                if obj.is_file
                    t = template_project_file.clone()
                    t.find(".project-file-name").text(obj.filename)
                    t.find(".project-file-last-edited").attr('title', obj.commit.date).timeago()
                    t.find(".project-file-last-commit-message").text(trunc(obj.commit.message, 70))
                else
                    t = template_project_directory.clone()
                    t.find(".project-directory-name").text(obj.filename)

                t.data('filename',obj.filename).click (e) ->
                    that.current_path.push($(@).data('filename'))
                    that.update_file_list_tab()

                file_or_listing.append(t)

    switch_displayed_branch: (new_branch) =>
        if new_branch != @meta.display_branch
            @meta.display_branch = new_branch
            @update_file_list_tab()
            @update_commits_tab()

    update_commits_tab: () =>
        {commit_list, commits} = @meta.logs[@meta.display_branch]

        # Set the selector that allows one to choose the current branch.
        select = @container.find(".project-commits-branch")
        select.empty()
        for branch in @meta.branches
            select.append($("<option>").text(branch).attr("value",branch))
        select.val(@meta.display_branch)
        that = @
        select.change  () ->
            that.switch_displayed_branch($(@).val())
            return false

        # Set the list of commits for the current branch.
        list = @container.find(".project-commits-list")
        list.empty()
        for id in commit_list
            entry = commits[id]
            t = template_project_commit_single.clone()
            t.find(".project-commit-single-message").text(trunc(entry.message, 80))
            t.find(".project-commit-single-author").text(entry.author)
            t.find(".project-commit-single-date").attr('title', entry.date).timeago()
            t.find(".project-commit-single-sha").text(id.slice(0,10))
            list.append(t)

    # Display all the branches, along with information about each one.
    update_branches_tab: () =>
        list = @container.find(".project-branches-list")
        list.empty()

        current_branch = @meta.current_branch
        @container.find(".project-branch").text(current_branch)
        that = @

        for branch in @meta.branches
            t = template_project_branch_single.clone()
            t.find(".project-branch-single-name").text(branch)
            if branch == current_branch
                t.addClass("project-branch-single-current")
                t.find("a[href=#checkout]").hide()
                #t.find("a[href=#compare]").hide()
                t.find("a[href=#merge]").hide()
            t.data('branch', branch)

            # TODO -- combine following three into a single loop

            # Make it so clicking on the "Checkout" button checks out a given branch.
            t.find("a[href=#checkout]").data("branch", branch).click (evt) ->
                branch = $(@).data('branch')
                that.branch_op(branch, 'checkout')
                return false

            t.find("a[href=#delete]").data("branch",branch).click (evt) ->
                branch = $(@).data('branch')
                # TODO -- stern warnings
                that.branch_op(branch, 'delete')
                return false

            t.find("a[href=#merge]").data("branch",branch).click (evt) ->
                branch = $(@).data('branch')
                # TODO -- stern warnings
                that.branch_op(branch, 'merge')
                return false

            list.append(t)

        @container.find(".project-branches").find("input").attr('placeholder',"Create a new branch from '#{current_branch}'...")

    #########################################
    # Operations on the current path
    #########################################

    # The user clicked the "delete" button for the current path.
    delete_current_path: () =>
        # Display confirmation modal.
        $("#project-delete-path-dialog").modal()
        # If they say yes, save current state and confirm success.
        # Actually do the delete.
        # Save result after doing delete.
        # Refresh.

    rename_current_path: () =>
        # Display modal dialog in which user can edit the filename
        $("#project-rename-path-dialog").modal()
        # Get the new filename and check if different
        # If so, send message
        # Save that rename happened.
        # Refresh.

    move_current_path: () =>
        # Display modal browser of all files in this project branch
        $("#project-move-path-dialog").modal()
        # Send move message
        # Save
        # Refresh


project_pages = {}

# Function that returns the project page for the project with given id,
# or creates it if it doesn't exist.
project_page = exports.project_page = (project) ->
    p = project_pages[project.project_id]
    if p?
        return p
    p = new ProjectPage(project)
    project_pages[project.project_id] = p
    return p


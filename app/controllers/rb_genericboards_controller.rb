include RbCommonHelper
include RbGenericboardsHelper

class RbGenericboardsController < RbApplicationController
  unloadable

  before_filter :find_rb_genericboard, :except => [ :index ]

  private

  def process_params(params, create=false)
    row_id = params.delete(:row_id)
    col_id = params.delete(:col_id)

    #determine issue tracker to use
    if col_id == 'rowelement'
      cls_hint = 'rowelement'
      object_type = @rb_genericboard.row_type
      rowelement = true
    else
      cls_hint = 'task'
      object_type = @rb_genericboard.element_type
      rowelement = false
    end
    if object_type.start_with? '__'
      render :text => e.message.blank? ? e.to_s : e.message, :status => 400
    end
    puts "Object type is #{object_type}"

    #determine project
    # 1. take project of parent (the row element)
    row_id = row_id.to_i
    row_object = @rb_genericboard.row_object(row_id)
    puts "Row object #{row_object}"
    col_id = col_id.to_i
    col_object = @rb_genericboard.col_object(col_id)
    puts "Col object #{col_object}"

    if (row_id > 0 && row_object.respond_to?(:project))
      project_id = row_object.project.id
      puts "Using row for project"
    elsif (col_id > 0 && col_object.respond_to?(:project))
      # 2. take project or column if applicable
      project_id = col_object.project.id
      puts "Using col for project"
    else
      # 3. fall back to current project
      project_id = @project.id
      puts "Using default project"
    end
    puts "Determined project to be #{project_id}"

    if create
      params[:tracker_id] = object_type.to_i if create#for create
      params[:project_id] = project_id
      if (row_object)
        parent = row_object
        if parent.is_a? RbGeneric
          params[:parent_issue_id] = parent.id
          params[:rbteam_id] = parent.rbteam_id unless parent.rbteam_id.blank?
          params[:release_id] = parent.release_id unless parent.release_id.blank?
          params[:fixed_version_id] = parent.fixed_version_id unless parent.fixed_version_id.blank?
        end
      end
      if (col_object)
        parent = col_object
        if parent.is_a? RbGeneric
          params[:parent_issue_id] = parent.id
          params[:rbteam_id] = parent.rbteam_id unless parent.rbteam_id.blank?
          params[:release_id] = parent.release_id unless parent.release_id.blank?
          params[:fixed_version_id] = parent.fixed_version_id unless parent.fixed_version_id.blank?
        end
      end
    end




    puts "Dealing with rowelement? #{rowelement}"
    if !rowelement
      puts "Dealing with rowelement? No."
      row_type = @rb_genericboard.row_type
      col_type = @rb_genericboard.col_type
      if row_type == '__sprint'
        params[:fixed_version_id] = row_id
      elsif col_type == '__sprint'
        params[:fixed_version_id] = col_id
      end

      if row_type == '__release'
        params[:release_id] = row_id
      elsif col_type == '__release'
        params[:release_id] = col_id
      end

      if row_type == '__team'
        params[:rbteam_id] = row_id
      elsif col_type == '__team'
        params[:rbteam_id] = col_id
      end

      if row_type == '__state'
        params[:status_id] = row_id
      elsif col_type == '__state'
        params[:status_id] = col_id
      end

      if (row_object)
        parent = row_object
        if parent.is_a? RbGeneric
          params[:parent_issue_id] = parent.id
          params[:project_id] = parent.project.id
          #params[:release_id] = parent.release_id unless parent.release_id.blank?
          #params[:fixed_version_id] = parent.fixed_version_id unless parent.fixed_version_id.blank?
        elsif parent.is_a? RbSprint
          params[:fixed_version_id] = parent.id
          #FIXME it seems that sharing scope is not obeyed, we might drag stories from non-shared project into sprints resulting in an error
        elsif parent.is_a? RbRelease
          params[:release_id] = parent.id
        elsif parent.is_a? Group
          params[:rbteam_id] = parent.id
        elsif col_object.is_a? IssueStatus
          params[:status_id] = col_object.id
        end
      end

      #override by col
      if (col_object)
        puts "We use col object for stuff #{col_object}"
        parent = col_object
        if parent.is_a? RbGeneric
          params[:parent_issue_id] = parent.id
          params[:project_id] = parent.project.id
          #params[:release_id] = parent.release_id unless parent.release_id.blank?
          #params[:fixed_version_id] = parent.fixed_version_id unless parent.fixed_version_id.blank?
        elsif parent.is_a? RbSprint
          params[:fixed_version_id] = parent.id
          #FIXME it seems that sharing scope is not obeyed, we might drag stories from non-shared project into sprints resulting in an error
        elsif parent.is_a? RbRelease
          puts "We use col object for release #{col_object}"
          params[:release_id] = parent.id
        elsif parent.is_a? Group
          params[:rbteam_id] = parent.id
        elsif col_object.is_a? IssueStatus
          params[:status_id] = col_object.id
        end
      end

      if (!row_object && !row_type.start_with?('__')) #row is RbGeneric, but no object
        params[:parent_issue_id] = nil
      end
      if col_type != object_type #not a single column board
        if (!col_object && !col_type.start_with?('__')) #col is RbGeneric, but no object
          params[:parent_issue_id] = nil
        end
      end

    end #if !rowelement


    puts "Determined #{params} parent #{params[:parent_issue_id]}, sprint #{params[:fixed_version_id]}, release #{params[:release_id]}, team #{params[:rbteam_id]}, project #{params[:project_id]}, status #{params[:status_id]}"

    return params, cls_hint
  end

  public

  def index
    board = RbGenericboard.order(:name).first
    if board
      redirect_to :controller => 'rb_genericboards', :action => 'show', :genericboard_id => board, :project_id => @project
      return
    end
    respond_to do |format|
      format.html { redirect_back_or_default(project_url(@project)) }
    end
  end

  def show
    @filteroptions = params.select{|k,v| k.starts_with?('__')}
    @rows = @rb_genericboard.rows(@project, @filteroptions).to_a
    @rows.append(RbFakeGeneric.new("No #{@rb_genericboard.row_type_name}"))
    @columns = @rb_genericboard.columns(@project, @filteroptions).to_a
    @elements_by_cell = @rb_genericboard.elements_by_cell(@project, @filteroptions)
    @all_boards = RbGenericboard.all

    respond_to do |format|
      format.html { render :layout => "rb" }
    end
  end

  def create
    params['author_id'] = User.current.id
    attrs, cls_hint = process_params(params, true)

    puts "Creating generic with attrs #{attrs}"
    begin
      story = RbGeneric.create_and_position(attrs)
    rescue => e
      render :text => e.message.blank? ? e.to_s : e.message, :status => 400
      return
    end

    if attrs[:parent_issue_id]
      story.parent_issue_id = attrs[:parent_issue_id]
      story.save!
    end


    status = (story.id ? 200 : 400)

    respond_to do |format|
      format.html { render :partial => "generic", :object => story, :status => status, :locals => {:cls => cls_hint} }
    end
  end

  def update
    story = RbGeneric.find(params[:id])
    attrs, cls_hint = process_params(params)

    puts "Genericboard update #{story} #{attrs} #{cls_hint} #{@rb_genericboard}"
    begin
      result = story.update_and_position!(attrs)
    rescue => e
      render :text => e.message.blank? ? e.to_s : e.message, :status => 400
      return
    end
    if attrs.include? :parent_issue_id
      story.parent_issue_id = attrs[:parent_issue_id]
      story.save!
    end

    status = (result ? 200 : 400)
    respond_to do |format|
      format.html { render :partial => "generic", :object => story, :status => status, :locals => {:cls => cls_hint} }
    end
  end

  def find_rb_genericboard
    @rb_genericboard = RbGenericboard.find(params[:genericboard_id])
  rescue ActiveRecord::RecordNotFound
    render_404
  end

end

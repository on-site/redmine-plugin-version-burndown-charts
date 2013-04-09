class VersionBurndownChartsController < ApplicationController
  unloadable
  menu_item :version_burndown_charts
  before_filter :find_project, :find_versions, :find_version_issues, :find_burndown_dates, :find_version_info, :find_issues_closed_status

  def index
    @graph =
      open_flash_chart_object( 1080, 750,
        url_for( :action => 'get_graph_data', :project_id => @project.id, :version_id => @version.id ),
          true, "plugin_assets/open_flash_chart/")
  end

  def get_graph_data
    estimated_data_array = []
    performance_data_array = []
    perfect_data_array = []
    upper_data_array = []
    lower_data_array = []
    x_labels_data = []

    index_estimated_hours = @estimated_hours
    index_performance_hours = @estimated_hours

    @days.each_with_index do |index_date, count|
      logger.debug("index_date #{index_date}")

      if index_date < @start_date
        # ready
        estimated_data_array << index_estimated_hours
        performance_data_array << index_performance_hours
        next
      elsif index_date == @start_date || index_date == @end_date
        x_labels_data << index_date.strftime("%m/%d")
      elsif @days.count > 20 && count % (@days.count / 3).round != 0
        x_labels_data << ""
      else
        x_labels_data << index_date.strftime("%m/%d")
      end

      estimated_data_array << round(index_estimated_hours -= calc_estimated_hours_by_date(index_date))
      index_performance_hours = calc_performance_hours_by_date(index_date)
      performance_data_array << round(@estimated_hours - index_performance_hours) if index_date <= Date.today
      perfect_data_array << 9
      upper_data_array << 0
      lower_data_array << 0

      logger.debug("#{index_date} index_estimated_hours #{round(index_estimated_hours)}")
      logger.debug("#{index_date} index_performance_hours #{round(index_performance_hours)}")
    end
    if perfect_data_array.last != 0
      # Add an extra day for the ideal line if the chart is going to
      # end on a day before the chart would go to zero.
      perfect_data_array << 0
      upper_data_array << 0
      lower_data_array << 0
    end
    perfect_data_array.fill {|i| round(@estimated_hours - (@estimated_hours / @ideal_days.count * i)) }
    upper_data_array.fill {|i| round((@estimated_hours - (@estimated_hours / @ideal_days.count * i)) * 1.2) }
    lower_data_array.fill {|i| round((@estimated_hours - (@estimated_hours / @ideal_days.count * i)) * 0.8) }
    create_graph(x_labels_data, estimated_data_array, performance_data_array, perfect_data_array, upper_data_array, lower_data_array)
  end

private

  def create_graph(x_labels_data, estimated_data_array, performance_data_array, perfect_data_array, upper_data_array, lower_data_array)
    chart =OpenFlashChart.new
    chart.set_title(Title.new("#{@version.name} #{l(:version_burndown_charts)}"))
    chart.set_bg_colour('#ffffff');

    x_legend = XLegend.new("#{l(:version_burndown_charts_xlegend)}")
    x_legend.set_style('{font-size: 20px; color: #000000}')
    chart.set_x_legend(x_legend)

    y_legend = YLegend.new("#{l(:version_burndown_charts_ylegend)}")
    y_legend.set_style('{font-size: 20px; color: #000000}')
    chart.set_y_legend(y_legend)

    x = XAxis.new
    x.set_range(0, @days.count, 1)
    x.set_labels(x_labels_data)
    chart.x_axis = x

    y = YAxis.new
    y.set_range(0, round(@estimated_hours * 1.2 + 1), (@estimated_hours / 6).round)
    chart.y_axis = y

    # add_line(chart, "#{l(:version_burndown_charts_upper_line)}", 1, '#dfdf3f', 4, upper_data_array)
    # add_line(chart, "#{l(:version_burndown_charts_lower_line)}", 1, '#3f3fdf', 4, lower_data_array)
    add_line(chart, "#{l(:version_burndown_charts_perfect_line)}", 3, '#bbbbbb', 6, perfect_data_array)
    # add_line(chart, "#{l(:version_burndown_charts_estimated_line)}", 2, '#00a497', 4, estimated_data_array)
    add_line(chart, "#{l(:version_burndown_charts_peformance_line)}", 3, '#bf0000', 6, performance_data_array)

    render :text => chart.to_s
  end

  def add_line(chart, text, width, colour, dot_size, values)
    my_line = Line.new
    my_line.text = text
    my_line.width = width
    my_line.colour = colour
    my_line.dot_size = dot_size
    my_line.values = values
    chart.add_element(my_line)
  end

  def is_leaf(issue)
    if !(defined?(issue.rgt) and defined?(issue.lft)) then
      return true
    end
    if issue.rgt - issue.lft == 1 then
      return true
    else
      return false
    end
  end

  def calc_estimated_hours_by_date(target_date)
    target_issues = @version_issues.select { |issue| issue.due_date == target_date}
    target_hours = 0
    target_issues.each do |issue|
      next unless is_leaf(issue)
      target_hours += round(issue.estimated_hours)
    end
    logger.debug("#{target_date} estimated hours = #{target_hours}")
    return target_hours
  end

  def calc_performance_hours_by_date(target_date)
    target_hours = 0
    @version_issues.each do |issue|
      next unless is_leaf(issue)
      target_hours += calc_issue_performance_hours_by_date(target_date, issue)
    end
    logger.debug("issues performance hours #{target_hours} #{target_date}")
    return target_hours
  end

  def calc_issue_performance_hours_by_date(target_date, issue)
    journals = issue.journals.select {|journal| (journal.created_on.to_date <= target_date)}
    if journals.empty?
      return 0
    end

    journal_details =
      journals.map(&:details).flatten.select {|detail| 'status_id' == detail.prop_key}

    journal_details.each do |journal_detail|
      logger.debug("journal_detail id #{journal_detail.id}")
      @closed_statuses.each do |closed_status|
        logger.debug("closed_status id #{closed_status.id}")
        if journal_detail.value.to_i == closed_status.id
          logger.debug("#{target_date} id #{issue.id}, issue.estimated_hours #{issue.estimated_hours}")
          return round(issue.estimated_hours)
        end
      end
    end

    journal_details_done_ratio =
      journals.map(&:details).flatten.select {|detail| 'done_ratio' == detail.prop_key}
    if journal_details_done_ratio.empty?
      return 0
    end

    target_hours = 0
    journal_details_done_ratio.each do |journal_detail|
      logger.debug("#{target_date} id #{issue.id}, journal_detail id #{journal_detail.id}, done_ratio #{journal_detail.old_value} -> #{journal_detail.value}")
      target_hours += round(issue.estimated_hours * (journal_detail.value.to_i - journal_detail.old_value.to_i) / 100)
    end

    logger.debug("#{target_date} id #{issue.id}, whole #{issue.estimated_hours}, done #{target_hours}")
    return target_hours
  end

  def round(value)
    unless value
      return 0
    else
      return (value.to_f * 1000.0).round / 1000.0
    end
  end

  def find_project

    logger.debug("params[:project_id].class #{params[:project_id].class}")

    if params[:project_id].blank?
      flash[:error] = l(:version_burndown_charts_project_nod_found, :project_id => 'parameter not found.')
      render_404
      return
    end

    begin
      @project = Project.find(params[:project_id])
    rescue ActiveRecord::RecordNotFound
      flash[:error] = l(:version_burndown_charts_project_nod_found, :project_id => params[:project_id])
      render_404
      return
    end
  end

  def find_versions
    versions = @project.versions.select(&:effective_date).sort_by(&:effective_date)
    @open_versions = versions.select{|version| version.status == 'open'}
    @locked_versions = versions.select{|version| version.status == 'locked'}
    @closed_versions = versions.select{|version| version.status == 'closed'}
    if params[:version_id]
      @version = Version.find(params[:version_id])
    else
      # First display case.
      @version = @open_versions.first || versions.last
    end

    logger.debug("@version.class #{@version.class}")
    logger.debug("@version.nil? #{@version.nil?}")

    if @version.blank?
      flash[:error] = l(:version_burndown_charts_no_version_with_due_date)
      render_404
      return
    end

    unless @version.due_date
      flash[:error] = l(:version_burndown_charts_version_due_date_not_found, :version_name => @version.name)
      render :action => "index" and return false
    end
  end

  def find_version_issues
    @version_issues = Issue.find_by_sql([
          "select * from issues
             where fixed_version_id = :version_id and start_date is not NULL and
               estimated_hours is not NULL order by start_date asc",
                 {:version_id => @version.id}])
    if @version_issues.empty?
      flash[:error] = l(:version_burndown_charts_issues_not_found, :version_name => @version.name)
      render :action => "index" and return false
    end
  end

  def find_burndown_dates
    @start_date = @version_issues[0].start_date
    if @version.due_date <= @start_date
      flash[:error] = l(:version_burndown_charts_version_start_date_invalid, :version_name => @version.name)
      render :action => "index" and return false
    end

    @end_date = @version.due_date
    unfinished_tickets = @version_issues.select {|x| x.done_ratio != 100.0 && x.closed_on.nil?}
    @end_date = Date.today if @end_date < Date.today && !unfinished_tickets.empty?

    # subtract off number of weekend days
    @ideal_days = (@start_date ... @version.due_date + 1).to_a.delete_if {|x| x.saturday? || x.sunday?}
    @days = (@start_date ... @end_date + 1).to_a.delete_if {|x| x.saturday? || x.sunday?}
    @start_date = @days.first
    @end_date = @days.last

    logger.debug("@start_date #{@start_date}")
    logger.debug("@end_date #{@end_date}")
  end

  def find_version_info
    @closed_pourcent = (@version.closed_pourcent * 100).round / 100
    @open_pourcent = 100 - @closed_pourcent
    unless @version.estimated_hours
      flash[:error] = l(:version_burndown_charts_issues_start_date_or_estimated_date_not_found, :version_name => @version.name)
      render :action => "index" and return false
    end
    @estimated_hours = round(@version.estimated_hours)
    logger.debug("@estimated_hours #{@estimated_hours}")
  end

  def find_issues_closed_status
    @closed_statuses = IssueStatus.find_all_by_is_closed(true)
    logger.debug("@closed_statuses #{@closed_statuses}")
  end
end

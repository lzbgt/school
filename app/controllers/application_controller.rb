require_dependency "user_sanitizer"

class ApplicationController < ActionController::Base
  before_filter :set_time_zone, :maybe_enqueue_badge_allocator, :maybe_enqueue_codewars_recorder

  protect_from_forgery
  helper_method :current_school

  rescue_from CanCan::AccessDenied do |exception|
    redirect_to root_path, :alert => exception.message
  end

  def current_school
    unless @current_school
      if params[:school]
        @current_school = School.find_by_slug(params[:school])
      elsif session[:school]
        @current_school = School.find_by_slug(session[:school])
      elsif current_user
        @current_school = current_user.school
      end
    end

    unless @current_school
      if @lesson
        @current_school = @lesson.venue.school
      end
    end

    unless @current_school
      begin
        loc = request.location
        @current_school = Venue.near([loc.latitude, loc.longitude], 5000)
                               .first
                               .school
      rescue StandardError
      end
    end

    unless @current_school
      @current_school = Venue.order("created_at").first.school
    end

    binding.pry unless @current_school
    session[:school] = @current_school.slug
    @current_school
  end

  def set_time_zone
    Time.zone = current_school.timezone
  end

  def devise_parameter_sanitizer
    if resource_class == User
      User::ParameterSanitizer.new(User, :user, params)
    else
      super
    end
  end

  private
  def maybe_enqueue_badge_allocator
    return unless user_signed_in?
    if current_user.last_badges_checked_at.nil? ||
       (Time.now - current_user.last_badges_checked_at > 3600)
      BadgeAllocator.perform_async(current_user.id)
      current_user.last_badges_checked_at = Time.now
      current_user.save!
    end
  end

  def maybe_enqueue_codewars_recorder
    return unless user_signed_in?
    return unless current_user.codewars_username.present?
    if current_user.last_codewars_checked_at.nil? ||
        (Time.now - current_user.last_codewars_checked_at > 3600)
      CodewarsRecorder.perform_async(current_user.id, current_user.codewars_username)
      current_user.last_codewars_checked_at = Time.now
      current_user.save!
    end
  end
end

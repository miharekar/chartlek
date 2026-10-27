class GoalsController < ApplicationController
  before_action :set_goal, only: %i[show edit update destroy]

  def index
    @goals = Goal.listed
    @today = Activity.today
  end

  def show
    @progress = @goal.progress
  end

  def new
    @goal = Goal.new(period: "month", starts_on: Activity.today)
    @goal.assign_attributes(params.permit(:period, :starts_on))
  end

  def edit
  end

  def create
    @goal = Goal.new(goal_params)

    if @goal.save
      redirect_to @goal
    else
      render :new, status: :unprocessable_content
    end
  end

  def update
    if @goal.update(goal_params)
      redirect_to @goal
    else
      render :edit, status: :unprocessable_content
    end
  end

  def destroy
    @goal.destroy
    redirect_to goals_path, status: :see_other
  end

  private
  def set_goal
    @goal = Goal.find(params.expect(:id))
  end

  def goal_params
    params.expect(goal: %i[period starts_on distance_km])
  end
end

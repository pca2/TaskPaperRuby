#! /usr/bin/env ruby
require_relative "./src/taskpaperdocument"
require "thor"
if ENV["TASKPAPER_PATH"].nil?
  puts "ERROR: must specify ENV['TASKPAPER_PATH']"
  exit 1
end
DOC = TaskPaperDocument.new(ENV["TASKPAPER_PATH"])

def get_project(project)
  existing_project = DOC.all_projects.find { |i| i.title == "#{project}" }
  if existing_project
    return existing_project
  else
    return DOC.add_child(TaskPaperItem.new("#{project}:"))
  end
end

def add_item_to_project(project, item)
  project.add_child("- #{item}")
  DOC.save_file
  puts "Added #{item} to #{project.title}"
end

class TPCLI < Thor
  desc "add TASK -p PROJECT -d done?", "Add TASK. PROJECT defaults to 'Inbox' if not specified"
  option :project_string, :default => ["Inbox"], :aliases => :p, :type => :array
  option :done, :default => false, :aliases => :d, :type => :boolean

  def add(*tasks)
    task_string = tasks.join(" ")
    if task_string.empty?
      puts "Error: Must specify task to add"
      exit 1
    end
    project_string = options[:project_string].join(" ")
    if options[:done]
      todays_date = Date.today.strftime("%Y-%m-%d")
      task_string = task_string + " @done(#{todays_date})"
    end
    project_obj = get_project(project_string)
    add_item_to_project(project_obj, task_string)
  end

  desc "today", "Return all undone tasks due today or tagged @today"

  def today
    items = DOC.due_today
    if items.empty?
      puts "No tasks with @today tag"
    end
    items.each do |item|
      puts "#{item}"
    end
  end

  desc "tomorrow", "Return all undone tasks due tomorrow"

  def tomorrow
    items = DOC.due_tomorrow
    if items.empty?
      puts "No tasks due tomorrow"
    end
    items.each do |item|
      puts "#{item}"
    end
  end

  desc "yesterday", "Return all tasks done yesterday"

  def yesterday
    items = DOC.done_yesterday
    if items.empty?
      puts "No tasks done yesterday"
    end
    items.each do |item|
      puts "#{item}"
    end
  end

  desc "tag TAG", "return all undone tasks with @TAG"

  def tag(tag)
    undone_tasks = DOC.all_tasks_not_done.select do |item|
      if item.has_tag? "#{tag}"
        true
      end
    end
    undone_tasks.each do |item|
      puts "#{item}"
    end
  end

  desc "project PROJECT", "return all tasks in PROJECT"

  def project(project_name)
    project_obj = get_project(project_name)
    puts project_obj.to_text
  end

  desc "projects", "list all projects"

  def projects
    all_projects = DOC.all_projects
    all_projects.each do |project|
      puts "#{project.title}"
    end
  end
end

#TODO: tasks completed yesterday

TPCLI.start(ARGV)

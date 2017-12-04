class Api::V1::StudentsController < ApplicationController

  def sign_up #works
    student = Student.create(first_name: params[:firstName], last_name: params[:lastName], email: params[:email])
    self.sign_in
  end

  def sign_in #works
    current_student = Student.find_by(email: params[:email])
    render json: {
      student: {
        id: current_student.id,
        email: current_student.email,
        firstName: current_student.first_name,
        lastName: current_student.last_name
      }
    }
  end

  def time_string_to_num(time)
    num = time.scan(/\d+|\D+/)
    num.delete_at(1)
    num[0] = num[2] == "PM" ? (num[0].to_i + 12).to_s : num[0]
    num.delete_at(2)
    return num.join(".").to_f
  end

  def check_for_course_conflicts(student)
    # get pattern & timeStart/timeEnd of new course
    new_pattern = params[:studentCourse][:pattern]
    new_start = self.time_string_to_num(params[:studentCourse][:timeStart])
    new_end = self.time_string_to_num(params[:studentCourse][:timeEnd])

    # get pattern & timeStart/timeEnd of all courses & components
    student_courses = StudentCourse.all.where(student_id: student.id)
    time_slots = []
    student_courses.each do |course|
      if course.student_course_components.length > 0
        course_and_comps = [{
          title_short: "#{course.parent.subject} #{course.parent.catalog_nbr}",
          pattern: course.pattern,
          time_start: self.time_string_to_num(course.time_start),
          time_end: self.time_string_to_num(course.time_end),
        }]
        course.student_course_components.each do |comp|
          course_and_comps.push({
            title_short: "#{comp.course_parent.subject} #{comp.course_parent.catalog_nbr}",
            pattern: comp.pattern,
            time_start: self.time_string_to_num(comp.time_start),
            time_end: self.time_string_to_num(comp.time_end),
          })
        end
        time_slots.push(course_and_comps)
      else
        time_slots.push({
          title_short: "#{course.parent.subject} #{course.parent.catalog_nbr}",
          pattern: course.pattern,
          time_start: self.time_string_to_num(course.time_start),
          time_end: self.time_string_to_num(course.time_end),
        })
      end
    end

    #check for conflicts with each time slot
    conflicts = []
    time_slots.flatten.each do |slot|
      if ((new_start > slot[:time_start]) && (new_start < slot[:time_end])) || ((new_end > slot[:time_start]) && (new_end < slot[:time_end]))
        conflicts.push(slot[:title_short])
      end
    end
    return conflicts
  end

  def convert_date_to_array(date)
    return [date.year, date.month - 1, date.day, date.hour, date.min]
  end

  def create_student_course_events(student_course, comp = false)
    if !comp
      parent = student_course.parent
      session_begin = parent.session_begin_dt.split("/").map {|t| t.to_i }
      session_end = parent.session_end_dt.split("/").map {|t| t.to_i }
    else
      session_begin = student_course.course_parent.session_begin_dt.split("/").map {|t| t.to_i }
      session_end = student_course.course_parent.session_end_dt.split("/").map {|t| t.to_i }
    end

    beginDt = DateTime.new(session_begin[2], session_begin[0], session_begin[1])
    endDt = DateTime.new(session_end[2], session_end[0], session_end[1])

    timeStart = student_course.time_start
    timeStart = timeStart.scan(/\d+|\D+/)
    timeStart.delete_at(1)
    timeStart[0] = (timeStart[2] == "PM" && timeStart[0] != "12") ? (timeStart[0].to_i + 12).to_s : timeStart[0]
    timeStart.delete_at(2)


    timeEnd = student_course.time_end
    timeEnd = timeEnd.scan(/\d+|\D+/)
    timeEnd.delete_at(1)
    timeEnd[0] = (timeEnd[2] == "PM" && timeEnd[0] != "12") ? (timeEnd[0].to_i + 12).to_s : timeEnd[0]
    timeEnd.delete_at(2)

    startDates = student_course.pattern.split("").map do |day|
      bgnDt = beginDt
      case day
      when "M"
        num = 0
      when "T"
        num = 1
      when "W"
        num = 2
      when "R"
        num = 3
      when "F"
        num = 4
      else
        break
      end
      bgnDt = bgnDt.next_week.advance(:days=>num)
      bgnDt = bgnDt.change({ hour: timeStart[0].to_i, min: timeStart[1].to_i })
    end

    startDates.each do |start|
      max = (endDt - start).floor
      count = 1
      while count < (max/7 + 1) do
        courseDt = start + (count * 7)

        courseDtEnd = courseDt.change({ hour: timeEnd[0].to_i, min: timeEnd[1].to_i })
        if !comp
          event = Event.create({
            title: "#{parent.subject} #{parent.catalog_nbr}",
            event_type: "course",
            start_date: courseDt,
            end_date: courseDtEnd
            })
          StudentCourseEvent.create({
            event_id: event.id,
            student_course_id: student_course.id
          })
        else
          event = Event.create({
            title: "#{student_course.component} #{student_course.course_parent.subject} #{student_course.course_parent.catalog_nbr}",
            event_type: "course",
            start_date: courseDt,
            end_date: courseDtEnd
          })
          StudCourseCompEvent.create({
            event_id: event.id,
            student_course_component_id: student_course.id
          })
        end
        count += 1
      end
    end
  end

  def create_due_dates(studentId)
    due_dates = []
    StudentCourse.all.where(student_id: studentId).each do |course|
      course.student_assignments.each do |assignment|
        event = Event.create({
          title: "DUE #{assignment.parent.title}",
          event_type: "assignment",
          start_date: assignment.parent.due_date,
          end_date: assignment.parent.due_date
        })
        StudentAssignmentEvent.create({
          event_id: event.id,
          student_assignment_id: assignment.id
        })
        this_event = {
          "title": "DUE #{assignment.parent.title}",
          "eventType": "assignment",
          "startDate": self.convert_date_to_array(assignment.parent.due_date),
          "endDate": self.convert_date_to_array(assignment.parent.due_date)
        }
        due_dates.push(this_event)
      end
    end
    return due_dates
  end


  def add_student_course # works
    student = Student.find(params[:student][:id])
    course = Course.find_or_create_by({
      crse_id: params[:studentCourse][:crseId],
      subject: params[:studentCourse][:subject],
      catalog_nbr: params[:studentCourse][:catalogNbr],
      title: params[:studentCourse][:title],
      description: params[:studentCourse][:description],
      units_minimum: params[:studentCourse][:unitsMinimum],
      units_maximum: params[:studentCourse][:unitsMaximum],
      session_begin_dt: params[:studentCourse][:sessionBeginDt],
      session_end_dt: params[:studentCourse][:sessionEndDt]
    })
    conflicts = self.check_for_course_conflicts(student)
    if conflicts.length > 0
      render json: { error: "This conflicts with: #{conflicts.join(',')}" }
    else
      student_course = StudentCourse.create({
        student_id: student.id,
        course_id: course.id,
        section: params[:studentCourse][:section],
        time_start: params[:studentCourse][:timeStart],
        time_end: params[:studentCourse][:timeEnd],
        pattern: params[:studentCourse][:pattern],
        facility_descr: params[:studentCourse][:facilityDescr],
        facility_descr_short: params[:studentCourse][:facilityDescrShort]
        })
        ##################
        self.create_student_course_events(student_course)
        student_course_events = student_course.events.map do |event|
          this_event = {
            'title': event.title,
            'eventType': event.event_type,
            'startDate': self.convert_date_to_array(event.start_date),
            'endDate': self.convert_date_to_array(event.end_date)
          }
        end

        components = []
        params[:studentCourse][:components].each do |component|
          student_course_comp = StudentCourseComponent.create({
            student_course_id: student_course.id,
            title: component[:title],
            component: component[:component],
            section: component[:section],
            time_start: component[:timeStart],
            time_end: component[:timeEnd],
            pattern: component[:pattern],
            facility_descr: component[:facilityDescr],
            facility_descr_short: component[:facilityDescrShort]
          })
          ##################
          self.create_student_course_events(student_course_comp, true)
          component_events = student_course_comp.events.map do |event|
            this_event = {
              'title': event.title,
              'eventType': event.event_type,
              'startDate': self.convert_date_to_array(event.start_date),
              'endDate': self.convert_date_to_array(event.end_date)
            }
          end
          student_course_events.push(component_events)
          components.push(student_course_comp)
        end

        formatted_components = self.format_components(components)

        instructors = params[:instructors] #will this be returned in the right format?
        instructors.each do |instructor|
          inst = Instructor.find_or_create_by({
            net_id: instructor[:netid],
            first_name: instructor[:firstName],
            last_name: instructor[:lastName]
          })
          StudentCourseInstructor.create({
            student_course_id: student_course.id,
            instructor_id: inst.id
          })
        end

        if course.assignments.length == 0
          student_assignments = self.create_mock_data(course, student, student_course) ###UPDATE LATER WITH BETTER DATA
        else
          student_assignments = self.add_student_assignments(course, student_course)
        end

        ##################
        # new_due_dates = self.create_due_dates(student.id)
        new_due_dates = self.create_due_dates(student.id)

        # add other assignment data for calendar later
        render json: {
          studentCourse: {
            studentCourseId: student_course.id,
            crseId: course.crse_id,
            section: student_course.section,
            title: student_course.parent.title,
            sessionBeginDt: student_course.parent.session_begin_dt,
            sessionEndDt: student_course.parent.session_end_dt,
            timeStart: student_course.time_start,
            timeEnd: student_course.time_end,
            pattern: student_course.pattern,
            completed: student_course.completed,
            facilityDescr: student_course.facility_descr,
            facilityDescrShort: student_course.facility_descr_short,
            subject: student_course.parent.subject,
            catalogNbr: student_course.parent.catalog_nbr,
            description: student_course.parent.description,
            components: formatted_components
          },
          studentAssignments: self.format_assignments(student_assignments),
          dueDates: new_due_dates,
          courseDates: student_course_events.flatten
        }
    end
  end



  def format_components(components)
    formatted_components = []
    components.each do |component|
      formatted_components.push({
        studentComponentId: component.id,
        studentCourseId: component.student_course_id,
        title: component.title,
        component: component.component,
        section: component.section,
        timeStart: component.time_start,
        timeEnd: component.time_end,
        pattern: component.pattern,
        facilityDescr: component.facility_descr,
        facilityDescrShort: component.facility_descr_short
      })
    end
    return formatted_components
  end

  def student_assignments # works
    student_course_dates = []
    student_assignments = []
    unformatted_assignments = []
    student_courses = StudentCourse.all.where(student_id: params[:studentId])
    student_courses.each do |student_course|
      assignments = student_course.student_assignments
      unformatted_assignments.push(assignments)
      student_assignments.push(self.format_assignments(assignments))
      student_course_dates.push(student_course.events)
    end

    student_course_dates = student_course_dates.flatten.map do |event|
      this_event = {
        'title': event.title,
        'eventType': event.event_type,
        "startDate": self.convert_date_to_array(event.start_date),
        "endDate": self.convert_date_to_array(event.end_date)
      }
    end

    student_due_dates = unformatted_assignments.flatten.map do |assignment|
      event = assignment.events[0]
      this_event = {
        'title': event.title,
        'eventType': event.event_type,
        "startDate": self.convert_date_to_array(event.start_date),
        "endDate": self.convert_date_to_array(event.end_date)
      }
    end

    render json: { studentAssignments: student_assignments.flatten, dueDates: student_due_dates, courseDates: student_course_dates }
  end

  def is_completed_parent(student_assignment, numSubs)
    student_assignment.parent.sub_assignments.each_with_index do |sub_ass, idx| #is from the class Assignment so need the Student's verions -->
      student_sub_ass = StudentAssignment.find_by(assignment_id: sub_ass.id, student_course_id: student_assignment.student_course_id)
      if !self.is_completed_parent(student_sub_ass, 0)
        return false
      end
      if (idx + 1) == numSubs
        return true
      end
    end
    return (!student_assignment.completed) ? false : true
  end

  def format_assignments(student_assignments) # works
    formatted_assignments = []
    assignments_seen = {}
    completed = false
    student_assignments.each do |student_assignment|
      if student_assignment.parent.sub_assignments.length > 0
        completed = self.is_completed_parent(student_assignment, student_assignment.parent.sub_assignments.length)
      else
        completed = student_assignment.completed
      end
      if completed != student_assignment.completed
        student_assignment.completed = completed
        student_assignment.save
      end
      if !!student_assignment.parent.primary_assignment_id && assignments_seen["#{student_assignment.parent.primary_assignment_id}"]
        assignments_seen["#{student_assignment.parent.id}"] = true
      else
        obj = {
          studentAssignmentId: student_assignment.id,
          studentCourseId: student_assignment.student_course.id,
          title: student_assignment.parent.title,
          description: student_assignment.parent.description,
          dueDate: student_assignment.parent.due_date,
          completed: student_assignment.completed,
          subAssignments: [],
          hasSubAssignments: student_assignment.parent.sub_assignments.length > 0 ? true : false,
          selectedNow: false,
          parentStudentAssignmentId: StudentAssignment.find_by(assignment_id: student_assignment.parent.primary_assignment_id, student_course_id: student_assignment.student_course_id) ? StudentAssignment.find_by(assignment_id: student_assignment.parent.primary_assignment_id, student_course_id: student_assignment.student_course_id).id : nil
        }
        formatted_assignments.push(obj)
        assignments_seen["#{student_assignment.parent.id}"] = true
      end
    end
    return formatted_assignments
  end

  def format_assignments_without_filter(student_assignments)
    formatted_assignments = []
    completed = false
    student_assignments.each do |student_assignment|
      if student_assignment.parent.sub_assignments.length > 0
        completed = self.is_completed_parent(student_assignment, student_assignment.parent.sub_assignments.length)
      else
        completed = student_assignment.completed
      end
      if completed != student_assignment.completed
        student_assignment.completed = completed
        student_assignment.save
      end
        obj = {
          studentAssignmentId: student_assignment.id,
          studentCourseId: student_assignment.student_course.id,
          title: student_assignment.parent.title,
          description: student_assignment.parent.description,
          dueDate: student_assignment.parent.due_date,
          completed: student_assignment.completed,
          subAssignments: [],
          hasSubAssignments: student_assignment.parent.sub_assignments.length > 0 ? true : false,
          selectedNow: false,
          parentStudentAssignmentId: StudentAssignment.find_by(assignment_id: student_assignment.parent.primary_assignment_id, student_course_id: student_assignment.student_course_id) ? StudentAssignment.find_by(assignment_id: student_assignment.parent.primary_assignment_id, student_course_id: student_assignment.student_course_id).id : nil
        }
        formatted_assignments.push(obj)
    end
    return formatted_assignments
  end



  def student_courses
    student_courses = StudentCourse.all.where(student_id: params[:studentId])
    formatted_student_courses = []
    student_courses.each do |student_course|
      formatted_student_courses.push({
          studentCourseId: student_course.id,
          section: student_course.section,
          title: student_course.parent.title,
          timeStart: student_course.time_start,
          timeEnd: student_course.time_end,
          pattern: student_course.pattern,
          completed: student_course.completed,
          facilityDescr: student_course.facility_descr,
          facilityDescrShort: student_course.facility_descr_short,
          subject: student_course.parent.subject,
          catalogNbr: student_course.parent.catalog_nbr,
          description: student_course.parent.description,
          components: self.format_components(student_course.student_course_components)
      })
    end
    render json: { studentCourses: formatted_student_courses }
  end

  def complete_assignment
    student_assignment = StudentAssignment.find(params[:studentAssignmentId])
    student_assignment.completed = !student_assignment.completed
    student_assignment.save
    if params[:isSubAssignment]
      root_assignments = params[:rootAssignmentIds].map { |id| StudentAssignment.find(id) }
      sub_assignments = params[:subAssignmentIds].map { |id| StudentAssignment.find(id) }
      sub_assignments.push(student_assignment)
      ids = params[:rootAssignmentIds].concat(params[:subAssignmentIds])
      render json: {
        ids: ids,
        subAssignments: self.format_assignments_without_filter(sub_assignments),
        rootAssignments: self.format_assignments(root_assignments)
      }
    else
      render json: { studentAssignment: self.format_assignments([student_assignment])[0] }
    end
  end

  def complete_parent_assignment
    parent_assignment = StudentAssignment.find(params[:studentAssignmentId])
    @@ids = [parent_assignment.id]
    parent_assignment.completed = !parent_assignment.completed
    parent_assignment.save
    if parent_assignment.completed
      self.complete_children(parent_assignment)
      render json: { ids: @@ids, completed: true }
    else
      self.incomplete_children(parent_assignment)
      render json: { ids: @@ids, completed: false }
    end

  end

  def complete_children(student_assignment)
    student_assignment.parent.sub_assignments.each_with_index do |sub_ass, idx| #is from the class Assignment so need the Student's verions -->
      student_sub_ass = StudentAssignment.find_by(assignment_id: sub_ass.id, student_course_id: student_assignment.student_course_id)
      @@ids.push(student_sub_ass.id)
      student_sub_ass.completed = true
      student_sub_ass.save
      self.complete_children(student_sub_ass)
    end
  end

  def incomplete_children(student_assignment)
    student_assignment.parent.sub_assignments.each_with_index do |sub_ass, idx| #is from the class Assignment so need the Student's verions -->
      student_sub_ass = StudentAssignment.find_by(assignment_id: sub_ass.id, student_course_id: student_assignment.student_course_id)
      @@ids.push(student_sub_ass.id)
      student_sub_ass.completed = false
      student_sub_ass.save
      self.complete_children(student_sub_ass)
    end
  end

  def complete_course
    student_course = StudentCourse.find(params[:studentCourseId])
    student_course.completed = true
    render json: {
      studentCourse: {
        studentCourseId: student_course.id,
        section: student_course.section,
        title: student_course.parent.title,
        timeStart: student_course.time_start,
        timeEnd: student_course.time_end,
        pattern: student_course.pattern,
        completed: student_course.completed,
        facilityDescr: student_course.facility_descr,
        facilityDescrShort: student_course.facility_descr_short,
        subject: student_course.parent.subject,
        catalogNbr: student_course.parent.catalog_nbr,
        description: student_course.parent.description
      }
    }
  end

  def get_sub_assignments # works
    student_assignment = StudentAssignment.find(params[:studentAssignmentId])
    student_sub_assignments = []
    student_assignment.parent.sub_assignments.each do |sub_assignment|
      student_sub_assignments.push(StudentAssignment.find_by(assignment_id: sub_assignment.id, student_course_id: student_assignment.student_course_id))
    end
    render json: {
      parentAssignmentId: params[:studentAssignmentId],
      subAssignments: self.format_assignments(student_sub_assignments),
      hasParent: student_assignment.parent.primary_assignment_id,
    }
  end


  def create_mock_data(course, student, student_course)
    student_assignments = []

    parent = student_course.parent
    session_begin = parent.session_begin_dt.split("/").map {|t| t.to_i }
    session_end = parent.session_end_dt.split("/").map {|t| t.to_i }

    beginDt = DateTime.new(session_begin[2], session_begin[0], session_begin[1])
    currDt = beginDt.next_week.advance(:days=>4).change({ hour: 17 })
    endDt = DateTime.new(session_end[2], session_end[0], session_end[1])
    i = 0

    while currDt < endDt do
      pri = Assignment.create({course_id: course.id, title: "#{course.title} assignment #{i+1}", description: "complete assignment ##{i+1}", due_date: currDt})
      student_assignments.push(StudentAssignment.create({assignment_id: pri.id, student_course_id: student_course.id}))
      if (i+1) % 4 == 0
        sub1a = Assignment.create({course_id: course.id, title: "#{course.title} assignment #{i+1}a", description: "complete assignment ##{i+1}a", due_date: currDt - 2, primary_assignment_id: pri.id})
        student_assignments.push(StudentAssignment.create({assignment_id: sub1a.id, student_course_id: student_course.id}))
      end
      if (i+1) % 8 == 0
        sub1a_a = Assignment.create({course_id: course.id, title: "#{course.title} assignment #{i+1}a_a", description: "complete assignment ##{i+1}a_a", due_date: currDt - 3, primary_assignment_id: sub1a.id})
        student_assignments.push(StudentAssignment.create({assignment_id: sub1a_a.id, student_course_id: student_course.id}))
        sub1a_b = Assignment.create({course_id: course.id, title: "#{course.title} assignment #{i+1}b_a", description: "complete assignment ##{i+1}a_b", due_date: currDt - 2, primary_assignment_id: sub1a.id})
        student_assignments.push(StudentAssignment.create({assignment_id: sub1a_b.id, student_course_id: student_course.id}))
      end
      currDt = currDt.next_week.advance(:days=>rand(5)).change({ hour: 17 })
      i += 1
    end
    return student_assignments
  end

  def add_student_assignments(course, student_course)
    student_assignments = course.assignments.map do |assignment|
      StudentAssignment.create({assignment_id: assignment.id, student_course_id: student_course.id})
    end
  end
  #
  # def create_mock_data(course, student, student_course)
  #   student_assignments = []
  #   5.times do |i|
  #     now = DateTime.now
  #     date = DateTime.new(now.year, now.month, now.day, 17, 0, 0, now.zone) + 10
  #     pri = Assignment.create({course_id: course.id, title: "#{course.title} assignment #{i+1}", description: "complete assignment ##{i+1}", due_date: date})
  #     student_assignments.push(StudentAssignment.create({assignment_id: pri.id, student_course_id: student_course.id}))
  #     if (i+1) % 2 == 0
  #       sub1a = Assignment.create({course_id: course.id, title: "#{course.title} assignment #{i+1}a", description: "complete assignment ##{i+1}a", due_date: date - 2, primary_assignment_id: pri.id})
  #       student_assignments.push(StudentAssignment.create({assignment_id: sub1a.id, student_course_id: student_course.id}))
  #       sub1b = Assignment.create({course_id: course.id, title: "#{course.title} assignment #{i+1}b", description: "complete assignment ##{i+1}b", due_date: date - 1, primary_assignment_id: pri.id})
  #       student_assignments.push(StudentAssignment.create({assignment_id: sub1b.id, student_course_id: student_course.id}))
  #     end
  #     if (i+1) % 4 == 0
  #       sub1a_a = Assignment.create({course_id: course.id, title: "#{course.title} assignment #{i+1}a_a", description: "complete assignment ##{i+1}a_a", due_date: date - 3, primary_assignment_id: sub1a.id})
  #       student_assignments.push(StudentAssignment.create({assignment_id: sub1a_a.id, student_course_id: student_course.id}))
  #       sub1b_a = Assignment.create({course_id: course.id, title: "#{course.title} assignment #{i+1}b_a", description: "complete assignment ##{i+1}b_a", due_date: date - 2, primary_assignment_id: sub1b.id})
  #       student_assignments.push(StudentAssignment.create({assignment_id: sub1b_a.id, student_course_id: student_course.id}))
  #     end
  #   end
  #   return student_assignments
  # end
  #
  # def add_student_assignments(course, student_course)
  #   student_assignments = course.assignments.map do |assignment|
  #     StudentAssignment.create({assignment_id: assignment.id, student_course_id: student_course.id})
  #   end
  # end


end

# studentAssignmentId: student_assignment.id,
# studentCourseId: student_assignment.student_course.id,
# title: student_assignment.parent.title,
# description: student_assignment.parent.description,
# dueDate: student_assignment.parent.due_date,
# completed: student_assignment.completed,
# subAssignments: [],
# hasSubAssignments: student_assignment.parent.sub_assignments.length > 0 ? true : false,
# selectedNow: false,
# parentStudentAssignmentId: StudentAssignment.find_by(assignment_id: student_assignment.parent.primary_assignment_id, student_course_id: student_assignment.student_course_id) ? StudentAssignment.find_by(assignment_id: student_assignment.parent.primary_assignment_id, student_course_id: student_assignment.student_course_id).id : nil

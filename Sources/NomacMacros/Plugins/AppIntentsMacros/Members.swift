/// The members each schema marks, as Xcode 27.0 marks them: the schemas home-assistant uses,
/// each observed with its members and with names it does not have (`macro_experiments.py`
/// `appintents-calendar`, `appintents-reminders`, `appintents-forms`). A name the schema does not
/// list here, `id` among them, is not marked. Other schemas: B-158.
let entityMembers: [String: [String: String]] = [
    "calendar.attendee": ["isAttendanceOptional": "@Property", "person": "@Property", "status": "@Property", "type": "@Property"],
    "calendar.calendar": ["title": "@Property"],
    "calendar.event": ["alarms": "@Property", "attendees": "@Property", "calendar": "@Property", "endDate": "@Property", "isAllDay": "@Property", "location": "@Property", "note": "@Property", "organizers": "@Property", "recurrence": "@Property", "startDate": "@Property", "status": "@Property", "title": "@Property", "travelTime": "@Property", "virtualLocation": "@Property"],
    "reminders.list": ["name": "@Property", "type": "@Property"],
    "reminders.locationTrigger": ["event": "@Property", "place": "@Property"],
    "reminders.reminder": ["completionDate": "@Property", "creationDate": "@Property", "dueDate": "@Property", "isCompleted": "@Property", "isFlagged": "@Property", "list": "@Property", "locationTrigger": "@Property", "note": "@Property", "recurrence": "@Property", "tags": "@Property", "title": "@Property", "urls": "@Property"],
    "reminders.section": ["list": "@Property", "name": "@Property"],
]

let intentMembers: [String: [String: String]] = [
    "calendar.createEvent": ["attendees": "@Parameter()", "calendar": "@Parameter()", "endDate": "@Parameter()", "isAllDay": "@Parameter()", "location": "@Parameter()", "note": "@Parameter()", "recurrence": "@Parameter()", "startDate": "@Parameter()", "title": "@Parameter()"],
    "calendar.deleteEvent": ["entity": "@Parameter()", "span": "@Parameter()"],
    "calendar.updateEvent": ["attendees": "@Parameter()", "calendar": "@Parameter()", "endDate": "@Parameter()", "event": "@Parameter()", "isAllDay": "@Parameter()", "location": "@Parameter()", "note": "@Parameter()", "recurrence": "@Parameter()", "span": "@Parameter()", "startDate": "@Parameter()", "title": "@Parameter()"],
    "reminders.createReminder": ["dueDate": "@Parameter()", "images": "@Parameter(supportedContentTypes: [.image])", "isFlagged": "@Parameter()", "list": "@Parameter()", "locationTrigger": "@Parameter()", "note": "@Parameter()", "recurrence": "@Parameter()", "section": "@Parameter()", "tags": "@Parameter()", "title": "@Parameter()", "urls": "@Parameter()"],
    "reminders.deleteReminders": ["entities": "@Parameter()"],
    "reminders.updateReminder": ["dueDate": "@Parameter()", "isCompleted": "@Parameter()", "isFlagged": "@Parameter()", "list": "@Parameter()", "locationTrigger": "@Parameter()", "note": "@Parameter()", "recurrence": "@Parameter()", "tags": "@Parameter()", "target": "@Parameter()", "title": "@Parameter()", "urls": "@Parameter()"],
]

/// The conformances a schema adds besides its kind's (`appintents-reminders`; `calendar.deleteEvent`
/// adds none).
let extraConformances: [String: [String]] = ["reminders.deleteReminders": ["DeleteIntent"]]

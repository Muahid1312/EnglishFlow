"""Build original, explicitly synthetic starter recordings; FFmpeg/Flite required."""
import hashlib,json,subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'listening_catalog'
lessons=[
 dict(id='planning-a-short-study-session',title='Planning a Short Study Session',level='B1',voice='slt',topic='Learning habits',transcript='''Maya has twenty minutes before dinner. She wants to practice English, but she does not want to spend the whole time choosing an activity. She opens her notebook and writes one small goal: understand a short recording and explain its main idea.

First, Maya listens without reading the transcript. She catches the topic, but misses one important detail. She does not stop at every unfamiliar word. Instead, she listens again with a specific question in mind: why did the speaker change the original plan?

On the second listening, the reason becomes clearer. Maya checks the transcript to confirm the words she heard. She chooses two useful expressions and writes her own example for each one. Then she records a brief summary in her own words.

At the end, she checks her goal. She can explain the main idea and support it with a detail from the recording. She also knows which part was difficult. Tomorrow, she can return to that part rather than start again without a plan.

A short study session does not need to include every possible activity. A clear goal, focused listening, and a small check of understanding can give the time a useful shape.''',questions=[('What is Maya’s main goal?',['Understand and summarize a short recording','Learn every unfamiliar word','Finish a long textbook'],'Understand and summarize a short recording'),('What question guides her second listening?',['Why the speaker changed the plan','How many people use the notebook','When dinner will finish'],'Why the speaker changed the plan'),('When does she check the transcript?',['After listening again','Before hearing the recording','Only after deleting her notes'],'After listening again'),('What helps her plan tomorrow’s session?',['Knowing which part was difficult','Choosing every possible activity','Avoiding the recording completely'],'Knowing which part was difficult')]),
 dict(id='clarifying-a-work-request',title='Clarifying a Work Request',level='B1',voice='rms',topic='Workplace communication',transcript='''A team leader asks Jordan to prepare a short update for Friday. Jordan understands the general topic, but the request leaves several questions open. Who will read the update? How long should it be? Does Friday mean the beginning or the end of the working day?

Instead of guessing, Jordan asks for clarification. He says, I can prepare the update. Could you confirm the audience and the deadline? His question shows that he is ready to do the work and wants to meet the real need.

The leader explains that the update is for new volunteers. It should describe the current tasks in plain language and arrive before the morning meeting. A technical report would not help this audience, even if all its information were correct.

Jordan repeats the key points in his own words. He will write a brief explanation for new volunteers and send it before the meeting on Friday morning. The leader confirms that this is right.

Later, one task changes. Jordan checks whether that change should appear in the update. He does not assume that the earlier instructions answer every new question.

Clear communication is not simply speaking more. Sometimes one useful question prevents several hours of work in the wrong direction. Asking politely and confirming the answer can help both people.''',questions=[('Why does Jordan ask questions?',['To understand what the task requires','To avoid preparing any update','To change the team leader’s role'],'To understand what the task requires'),('Who is the update for?',['New volunteers','Only technical specialists','The general public everywhere'],'New volunteers'),('When is it needed?',['Before Friday’s morning meeting','After Friday’s last meeting','At any time next month'],'Before Friday’s morning meeting'),('What does Jordan do when a task changes?',['Checks whether to include the change','Assumes the old instructions settle it','Deletes the whole update immediately'],'Checks whether to include the change')]),
 dict(id='evidence-behind-a-confident-claim',title='The Evidence Behind a Confident Claim',level='B2',voice='slt',topic='Critical thinking',transcript='''A neighborhood group is considering a new booking system. A confident presentation describes it as a success because nearly everyone who completed the online form received an appointment. The statement sounds convincing, but one resident asks what happened to the people who never completed the form.

That question changes the scope of the discussion. A success rate among completed applications does not necessarily describe everyone who tried to obtain help. Some people may have stopped because the instructions were unclear, a device was unsuitable, or an alternative booking route was difficult to find.

The group does not dismiss the positive results. Completed appointments are useful evidence. However, it separates that observation from the broader claim that the system works well for all residents. To investigate the broader claim, the group needs information about barriers as well as successful outcomes.

Members suggest reviewing abandoned applications and asking about experiences through several accessible routes. They also agree to explain how participants were contacted. Otherwise, the investigation might overlook the same people whose difficulties started the discussion.

The final report therefore includes a more careful conclusion. The system appears useful for a particular group under the conditions observed. Further work is needed to understand who faces obstacles and which changes could reduce them.

A qualification does not automatically make a claim weak. It can make the relationship between the evidence and the conclusion clearer, giving the next investigation a better starting point.''',questions=[('What is the main concern?',['Whether the success claim includes people who could not finish','Whether all completed appointments should be ignored','Whether confident speaking is always dishonest'],'Whether the success claim includes people who could not finish'),('Which group is missing from the original success rate?',['People who did not complete the form','Everyone who received an appointment','Only the people giving the presentation'],'People who did not complete the form'),('Why explain how participants were contacted?',['To assess who the investigation may have missed','To guarantee that no barrier exists','To replace all information about outcomes'],'To assess who the investigation may have missed'),('What does a qualification contribute here?',['A clearer boundary around the conclusion','A promise of universal success','Proof that every positive result is false'],'A clearer boundary around the conclusion')]),
 dict(id='testing-a-change-before-expanding-it',title='Testing a Change Before Expanding It',level='B2',voice='rms',topic='Practical problem solving',transcript='''A community workshop wants to replace its printed instructions with a shared digital guide. The proposal promises easier updates and fewer outdated copies. Before changing every activity, the coordinator suggests a limited trial with one workshop group.

The trial begins with a clear question: can participants find and follow the instructions they need? The team records the existing process so that later observations have a useful point of comparison. It also keeps an accessible alternative available while the trial is running.

Early feedback reveals an important distinction. Some participants can open the guide but struggle to identify the current version. Others understand the layout but cannot use a required device comfortably. Treating both experiences as the same problem would lead to an incomplete response.

The team revises the version labels and asks qualified support staff to review the access difficulties. It then tests the revised arrangement rather than assuming that making a change proves the problem has been solved. The coordinator records which decisions were made and why, so another team can evaluate the reasoning later.

The trial does not establish that the guide will suit every future group. It provides evidence about specific conditions, identifies remaining limitations, and shows what a larger investigation should examine.

A useful pilot project is therefore more than a smaller launch. It is a chance to learn before the cost of changing direction becomes greater. Success includes discovering a problem early enough to respond responsibly.''',questions=[('What makes this a useful trial?',['It tests a specific question and records what is learned','It guarantees every future group will succeed','It removes every alternative immediately'],'It tests a specific question and records what is learned'),('What distinction appears in the feedback?',['Finding the current version differs from using a device comfortably','All access difficulties have one identical cause','Opening a guide always proves understanding'],'Finding the current version differs from using a device comfortably'),('Why test the revised arrangement?',['A change still needs evidence that it helps','Every revision automatically resolves a problem','Earlier feedback must be discarded'],'A change still needs evidence that it helps'),('What does the trial establish?',['Evidence and limits under the conditions examined','An official qualification for every participant','A result that applies to every future workshop'],'Evidence and limits under the conditions examined')])]
for lesson in lessons:
 text=OUT/(lesson['id']+'.txt');text.write_text(lesson['transcript']+'\n',encoding='utf-8')
 audio=OUT/'media'/(lesson['id']+'.mp3')
 subprocess.run(['ffmpeg','-nostdin','-y','-hide_banner','-loglevel','error','-f','lavfi','-i',f'flite=textfile={text}:voice={lesson["voice"]}','-ar','24000','-ac','1','-b:a','64k',str(audio)],check=True)
 duration=float(subprocess.check_output(['ffprobe','-v','error','-show_entries','format=duration','-of','default=noprint_wrappers=1:nokey=1',str(audio)]))
 lesson.update(duration_ms=round(duration*1000),bytes=audio.stat().st_size,sha256=hashlib.sha256(audio.read_bytes()).hexdigest(),file=audio.name,accent='American',speaker=f'CMU Flite {lesson["voice"].upper()} synthetic voice',provider='LexiFlow originals')
 lesson['questions']=[dict(prompt=q,choices=c,answer=a) for q,c,a in lesson['questions']]
(OUT/'lessons.json').write_text(json.dumps(dict(version=1,lessons=lessons),ensure_ascii=False,indent=2)+'\n')
print([(l['id'],l['bytes'],l['duration_ms']) for l in lessons])

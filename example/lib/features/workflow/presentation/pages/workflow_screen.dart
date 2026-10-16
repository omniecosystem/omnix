import 'dart:async';
import 'package:flutter/material.dart';
import '../../data/repositories/workflow_repository.dart';
import '../controllers/workflow_controller.dart';
import '../widgets/workflow_panel.dart';
import '../../data/repositories/event_task_repository.dart';
import '../controllers/event_tasks_controller.dart';
import '../widgets/event_tasks_panel.dart';

class WorkflowScreen extends StatefulWidget {
  const WorkflowScreen({super.key});
  @override
  State<WorkflowScreen> createState() => _WorkflowScreenState();
}

class _WorkflowScreenState extends State<WorkflowScreen> {
  final controller = WorkflowController(WorkflowRepository());
  final tasks = EventTasksController(EventTaskRepository());
  @override
  void initState() {
    super.initState();
    unawaited(controller.initialize());
    unawaited(tasks.refresh());
  }

  @override
  void dispose() {
    unawaited(
      controller.shutdown().catchError(
        (Object e) => debugPrint('Workflow close: $e'),
      ),
    );
    controller.dispose();
    tasks.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 2,
    child: Column(
      children: [
        const TabBar(
          tabs: [
            Tab(text: 'Event tasks'),
            Tab(text: 'Recovery demo'),
          ],
        ),
        Expanded(
          child: TabBarView(
            children: [
              ListenableBuilder(
                listenable: tasks,
                builder: (_, _) => EventTasksPanel(
                  tasks: tasks.tasks,
                  queuedJobs: tasks.queuedJobs,
                  busy: tasks.busy,
                  error: tasks.error,
                  notice: tasks.notice,
                  onRefresh: tasks.refresh,
                  onStop: tasks.stop,
                  onSimulate: tasks.simulate,
                  proposals: tasks.proposals,
                  jobs: tasks.jobs,
                  onAccept: tasks.accept,
                  onTick: tasks.tick,
                  onJobAction: tasks.act,
                  activeJob: tasks.activeJob,
                  onCancelActive: tasks.cancelActive,
                ),
              ),
              ListenableBuilder(
                listenable: controller,
                builder: (_, _) => WorkflowPanel(
                  progress: controller.progress,
                  busy: controller.busy,
                  executing: controller.executing,
                  error: controller.error,
                  onRun: controller.runNext,
                  onRecover: controller.recover,
                  onConfirm: controller.confirmSimulation,
                  onReopen: controller.reopen,
                  onNew: controller.newDemo,
                  onCancel: controller.cancel,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

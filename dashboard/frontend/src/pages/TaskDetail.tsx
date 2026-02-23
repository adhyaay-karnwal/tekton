import { useEffect, useState } from 'react';
import { useParams, useNavigate, Link } from 'react-router-dom';
import { useQuery } from '@tanstack/react-query';
import { ChevronLeft } from 'lucide-react';
import LogViewer from '@/components/LogViewer';
import TaskChat from '@/components/TaskChat';
import { getTask, connectTaskOutput, listSubtasks, getMe } from '@/lib/api';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { Badge } from '@/components/ui/badge';
import { Separator } from '@/components/ui/separator';
import { statusVariant } from '@/lib/status';

const CHAT_STATUSES = ['awaiting_followup', 'running_claude'];

export default function TaskDetail() {
  const { id } = useParams<{ id: string }>();
  const navigate = useNavigate();
  const [ws, setWs] = useState<WebSocket | null>(null);
  const [connected, setConnected] = useState(false);

  const { data: task } = useQuery({
    queryKey: ['task', id],
    queryFn: () => getTask(id!),
    enabled: !!id,
    refetchInterval: 3000,
  });

  const { data: subtasks } = useQuery({
    queryKey: ['subtasks', id],
    queryFn: () => listSubtasks(id!),
    enabled: !!id,
  });

  const { data: me } = useQuery({
    queryKey: ['me'],
    queryFn: getMe,
  });

  useEffect(() => {
    if (!id) return;

    const socket = connectTaskOutput(id);
    socket.addEventListener('open', () => setConnected(true));
    socket.addEventListener('close', () => setConnected(false));
    setWs(socket);

    return () => {
      socket.close();
    };
  }, [id]);

  const showChat = task && CHAT_STATUSES.includes(task.status);

  return (
    <div>
      <div className="flex items-center gap-3 mb-6">
        <Button variant="ghost" size="sm" onClick={() => navigate('/tasks')}>
          <ChevronLeft className="size-4" />
          Tasks
        </Button>
        <h1 className="text-2xl font-bold font-mono">{id?.slice(0, 8)}</h1>
        {task && <Badge variant={statusVariant(task.status).variant} className={statusVariant(task.status).className}>{task.status}</Badge>}
        <Badge variant={connected ? 'default' : 'outline'}>
          {connected ? 'Live' : 'Disconnected'}
        </Badge>
      </div>

      {task && (
        <Card className="mb-6">
          <CardContent className="py-4">
            {task.parent_task_id && (
              <>
                <div className="mb-3">
                  <span className="text-muted-foreground text-sm">Parent Task</span>
                  <p className="mt-1">
                    <Link
                      to={`/tasks/${task.parent_task_id}`}
                      className="font-mono text-sm text-blue-400 hover:text-blue-300"
                    >
                      {task.parent_task_id.slice(0, 8)}
                    </Link>
                  </p>
                </div>
                <Separator className="mb-3" />
              </>
            )}
            <div className="grid grid-cols-2 md:grid-cols-4 gap-4 text-sm">
              <div>
                <span className="text-muted-foreground">Repo</span>
                <p>{task.repo}</p>
              </div>
              <div>
                <span className="text-muted-foreground">Base</span>
                <p>{task.base_branch}</p>
              </div>
              {task.branch_name && (
                <div>
                  <span className="text-muted-foreground">Branch</span>
                  <p className="font-mono">{task.branch_name}</p>
                </div>
              )}
              {task.preview_url && (
                <div>
                  <span className="text-muted-foreground">Preview</span>
                  <p>
                    <a
                      href={task.preview_url}
                      target="_blank"
                      rel="noopener noreferrer"
                      className="text-blue-400 hover:text-blue-300"
                    >
                      {task.preview_slug}
                    </a>
                  </p>
                </div>
              )}
              {task.created_by && (
                <div>
                  <span className="text-muted-foreground">Created by</span>
                  <p className="truncate">{task.created_by}</p>
                </div>
              )}
            </div>
            <Separator className="my-3" />
            <div>
              <span className="text-muted-foreground text-sm">Prompt</span>
              <p className="mt-1 text-sm whitespace-pre-wrap">{task.prompt}</p>
            </div>
            {task.error_message && (
              <>
                <Separator className="my-3" />
                <div>
                  <span className="text-destructive text-sm">Error</span>
                  <p className="mt-1 text-sm text-destructive">{task.error_message}</p>
                </div>
              </>
            )}
            {task.screenshot_url && (
              <>
                <Separator className="my-3" />
                <div>
                  <span className="text-muted-foreground text-sm">Preview Screenshot</span>
                  <div className="mt-2">
                    <a href={task.screenshot_url} target="_blank" rel="noopener noreferrer">
                      <img
                        src={task.screenshot_url}
                        alt="Preview screenshot"
                        className="max-w-full rounded-md border border-border hover:opacity-90 transition-opacity"
                        style={{ maxHeight: '300px', objectFit: 'contain' }}
                      />
                    </a>
                  </div>
                </div>
              </>
            )}
          </CardContent>
        </Card>
      )}

      {showChat && me && (
        <TaskChat taskId={id!} currentUserEmail={me.email} />
      )}

      {subtasks && subtasks.length > 0 && (
        <Card className="mb-6">
          <CardHeader className="py-3">
            <CardTitle className="text-base">Subtasks</CardTitle>
          </CardHeader>
          <CardContent className="pt-0">
            <div className="space-y-2">
              {subtasks.map((sub) => (
                <Link key={sub.id} to={`/tasks/${sub.id}`}>
                  <Card className="hover:border-muted-foreground/25 transition-colors">
                    <CardContent className="py-3">
                      <div className="flex items-center justify-between mb-1">
                        <span className="font-mono text-sm text-muted-foreground">
                          {sub.id.slice(0, 8)}
                        </span>
                        <Badge variant={statusVariant(sub.status).variant} className={statusVariant(sub.status).className}>
                          {sub.status}
                        </Badge>
                      </div>
                      <p className="text-sm line-clamp-1">{sub.prompt}</p>
                    </CardContent>
                  </Card>
                </Link>
              ))}
            </div>
          </CardContent>
        </Card>
      )}

      <Card>
        <CardHeader className="py-3">
          <CardTitle className="text-base">Live Logs</CardTitle>
        </CardHeader>
        <CardContent className="p-0">
          <LogViewer ws={ws} />
        </CardContent>
      </Card>
    </div>
  );
}

-----------------------------------------------------------------------------
-- |
-- Module      :  FindFirstConcurrent
-- Maintainer  :  Philippe Heim (Heim@ProjectJARVIS.de)
--
-- An toolbox to execute multiple things in parallel and find
-- the first matching one
--
-----------------------------------------------------------------------------
module CoreGeneration.FindFirstConcurrent
  ( incParallelFirst
  ) where

-----------------------------------------------------------------------------
import Data.Set as Set (Set, delete, empty, fromList, insert, toList)

import Control.Concurrent.MVar (MVar, newEmptyMVar, putMVar, takeMVar)

import Control.Concurrent (ThreadId, forkOS, killThread, myThreadId)

-----------------------------------------------------------------------------
-- | Given a list of IO tasks (returning a Mabye) and a pool size incParallelFirst 
-- incParallelFirst returns the first Just value that some of these tasks return.
-- The tasks are executetd in the order of the list and not more then the size of
-- the pool
incParallelFirst :: Int -> [IO (Maybe a)] -> IO (Maybe a)
incParallelFirst poolSize values =
  let initial = take poolSize values
      rest = drop poolSize values
   in do semaphore <- newEmptyMVar
         initialThreads <- traverse (`startWorker` semaphore) initial
         loop semaphore (fromList initialThreads) rest
  where
    loop semaphore threads queue =
      if threads == empty
        then return Nothing
        else do
          out <- takeMVar semaphore
          case out of
            (_, Just a) -> do
              killWorkers threads
              return $ Just a
            (id, Nothing) -> do
              let threads' = delete id threads
              (threads'', queue') <-
                case queue of
                  [] -> return (threads', [])
                  q:qr -> do
                    newId <- startWorker q semaphore
                    return (insert newId threads', qr)
              loop semaphore threads'' queue'

-----------------------------------------------------------------------------
-- | Kills all threads in the given pool
killWorkers :: Set ThreadId -> IO ()
killWorkers threads = sequence_ (killThread <$> toList threads)

-----------------------------------------------------------------------------
-- | Starts a worker who – after finishing his task – put the his result and
--thread id into the MVar (he blocks until it is free) and gives back the thread 
--id of the started worker
startWorker :: IO a -> MVar (ThreadId, a) -> IO ThreadId
startWorker op semaphore = forkOS (worker op semaphore)
  where
    worker :: IO a -> MVar (ThreadId, a) -> IO ()
    worker op semaphore = do
      id <- myThreadId
      result <- op
      putMVar semaphore (id, result)
